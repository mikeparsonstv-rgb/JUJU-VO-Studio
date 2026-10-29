import Foundation
import GRDB
import BroadcastWave
#if canImport(AVFoundation)
@preconcurrency import AVFoundation
#endif

/// Delivery formats. Anything other than `.native` is a recorded derivative — never a silent conversion.
public enum DeliveryFormat: String, Sendable, CaseIterable, Codable {
    case native                 // the take's own bytes, unchanged
    case broadcast48k24         // 48 kHz, 24-bit PCM, same channel count; sample-rate converted, no level change

    public var label: String {
        switch self { case .native: "Native (as rendered)"; case .broadcast48k24: "Broadcast 48 kHz / 24-bit" }
    }
}

extension StudioSchema {
    static func registerStage3(_ m: inout DatabaseMigrator) {
        m.registerMigration("v3-delivery-derivatives") { db in
            try db.alter(table: "wavExport") { t in
                t.add(column: "deliveryFormat", .text).notNull().defaults(to: "native")
                t.add(column: "conversionNote", .text)
            }
        }
    }
}

public enum DeliveryConverter {
    public enum ConversionError: Error, LocalizedError {
        case unavailable, failed(String)
        public var errorDescription: String? {
            switch self { case .unavailable: "Sample-rate conversion isn't available on this platform."
            case .failed(let w): "Couldn't convert the audio: \(w)" }
        }
    }

    /// Writes a 48 kHz / 24-bit PCM version of `source` to `dest` and describes exactly what was done.
    public static func broadcast48k24(source: URL, dest: URL) throws -> String {
        #if canImport(AVFoundation)
        do {
            let input = try AVAudioFile(forReading: source)
            let inFormat = input.processingFormat
            guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: inFormat.channelCount, interleaved: false),
                  let converter = AVAudioConverter(from: inFormat, to: outFormat) else { throw ConversionError.failed("no converter") }
            converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
            converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: inFormat.channelCount,
                                           AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            let output = try AVAudioFile(forWriting: dest, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: 8192)!
            var done = false
            while true {
                let outBuf = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: 16384)!
                var err: NSError?
                let status = converter.convert(to: outBuf, error: &err) { _, outStatus in
                    if done { outStatus.pointee = .endOfStream; return nil }
                    do { try input.read(into: inBuf) } catch { outStatus.pointee = .endOfStream; done = true; return nil }
                    if inBuf.frameLength == 0 { outStatus.pointee = .endOfStream; done = true; return nil }
                    outStatus.pointee = .haveData; return inBuf
                }
                if let err { throw ConversionError.failed(err.localizedDescription) }
                if outBuf.frameLength > 0 { try output.write(from: outBuf) }
                if status == .endOfStream || status == .error { break }
            }
            return String(format: "Derivative: %.0f Hz → 48000 Hz (Apple mastering-quality SRC), %d-bit → 24-bit PCM, %d ch. No level, loudness or timing change.",
                          inFormat.sampleRate, Int(input.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int ?? 0), Int(inFormat.channelCount))
        } catch let e as ConversionError { throw e } catch { throw ConversionError.failed(error.localizedDescription) }
        #else
        throw ConversionError.unavailable
        #endif
    }
}
