import AVFoundation
import Foundation
import RB007TimingRepair

func value(_ flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

func fail(_ message: String) -> Never {
    fputs("error: \(message)\n", stderr)
    exit(2)
}

func readBuffer(file: AVAudioFile, startFrame: AVAudioFramePosition, frameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
        throw NSError(domain: "RB007", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate audio buffer"])
    }
    file.framePosition = startFrame
    try file.read(into: buffer, frameCount: frameCount)
    return buffer
}

func writeSilence(frames: AVAudioFrameCount, format: AVAudioFormat, to output: AVAudioFile) throws {
    guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
    buffer.frameLength = frames
    if let channels = buffer.floatChannelData {
        for channel in 0..<Int(format.channelCount) {
            channels[channel].initialize(repeating: 0, count: Int(frames))
        }
    }
    try output.write(from: buffer)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let inputPath = value("--input", in: arguments),
      let outputPath = value("--output", in: arguments),
      let onsetText = value("--onset", in: arguments), let onset = Double(onsetText),
      let offsetText = value("--offset", in: arguments), let offset = Double(offsetText),
      let targetText = value("--target-span", in: arguments), let targetSpan = Double(targetText) else {
    fail("usage: rb007-time-repair --input PATH --output PATH --onset SECONDS --offset SECONDS --target-span SECONDS")
}
let inputURL = URL(fileURLWithPath: inputPath)
let outputURL = URL(fileURLWithPath: outputPath)
guard !FileManager.default.fileExists(atPath: outputURL.path) else { fail("refusing to overwrite output") }

do {
    let input = try AVAudioFile(forReading: inputURL)
    let format = input.processingFormat
    let sampleRate = format.sampleRate
    let onsetFrame = max(0, min(input.length, AVAudioFramePosition((onset * sampleRate).rounded())))
    let offsetFrame = max(onsetFrame + 1, min(input.length, AVAudioFramePosition((offset * sampleRate).rounded())))
    let regionFrames = AVAudioFrameCount(offsetFrame - onsetFrame)
    let targetFrames = AVAudioFrameCount((targetSpan * sampleRate).rounded())
    let timeScale = Double(targetFrames) / Double(regionFrames)
    guard TimingRepairPlan.minimumTimeScale...TimingRepairPlan.maximumTimeScale ~= timeScale else {
        fail("time scale \(timeScale) outside guardrail")
    }
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: format.channelCount, AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    let output = try AVAudioFile(forWriting: outputURL, settings: settings, commonFormat: .pcmFormatFloat32,
                                 interleaved: false)
    if onsetFrame > 0 {
        try output.write(from: readBuffer(file: input, startFrame: 0, frameCount: AVAudioFrameCount(onsetFrame)))
    }

    let region = try readBuffer(file: input, startFrame: onsetFrame, frameCount: regionFrames)
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let timePitch = AVAudioUnitTimePitch()
    timePitch.pitch = 0
    timePitch.rate = Float(1 / timeScale)
    engine.attach(player)
    engine.attach(timePitch)
    engine.connect(player, to: timePitch, format: format)
    engine.connect(timePitch, to: engine.mainMixerNode, format: format)
    let maximumFrames: AVAudioFrameCount = 4_096
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maximumFrames)
    player.scheduleBuffer(region, at: nil, options: [])
    try engine.start()
    player.play()
    let algorithmLatencySeconds = timePitch.latency
    var latencyFramesRemaining = AVAudioFrameCount((algorithmLatencySeconds * sampleRate).rounded(.up))
    while latencyFramesRemaining > 0 {
        let requested = min(maximumFrames, latencyFramesRemaining)
        guard let discard = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: requested) else { fail("latency buffer allocation failed") }
        let status = try engine.renderOffline(requested, to: discard)
        switch status {
        case .success:
            latencyFramesRemaining -= discard.frameLength
        case .cannotDoInCurrentContext, .insufficientDataFromInputNode:
            continue
        case .error:
            fail("AVAudioEngine latency render failed")
        @unknown default:
            fail("Unknown AVAudioEngine latency render status")
        }
    }
    var remaining = targetFrames
    while remaining > 0 {
        let requested = min(maximumFrames, remaining)
        guard let render = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: requested) else { fail("render allocation failed") }
        let status = try engine.renderOffline(requested, to: render)
        switch status {
        case .success:
            if render.frameLength > 0 {
                try output.write(from: render)
                remaining -= render.frameLength
            }
        case .cannotDoInCurrentContext, .insufficientDataFromInputNode:
            continue
        case .error:
            fail("AVAudioEngine offline render failed")
        @unknown default:
            fail("Unknown AVAudioEngine render status")
        }
    }
    player.stop(); engine.stop()
    let tailFrames = input.length - offsetFrame
    if tailFrames > 0 {
        try output.write(from: readBuffer(file: input, startFrame: offsetFrame, frameCount: AVAudioFrameCount(tailFrames)))
    }
    let response: [String: Any] = [
        "schema_version": 1, "algorithm": "AVAudioUnitTimePitch",
        "backend": "AVFAudio/AVAudioEngine offline manual rendering",
        "platform": ProcessInfo.processInfo.operatingSystemVersionString,
        "algorithm_latency_seconds_discarded": algorithmLatencySeconds,
        "pitch_cents": 0, "playback_rate": 1 / timeScale, "time_scale": timeScale,
        "source_region_frames": regionFrames, "target_region_frames": targetFrames,
        "sample_rate_hz": sampleRate, "channels": format.channelCount,
    ]
    let data = try JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
} catch {
    fail(error.localizedDescription)
}
