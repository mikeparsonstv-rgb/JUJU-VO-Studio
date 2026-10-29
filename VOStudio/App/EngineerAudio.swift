import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Speech
import VOStudioCore

/// The Engineer's speaking voice: Apple on-device speech (no download, no network). Returns when finished.
@MainActor
final class SystemEngineerVoice: NSObject, EngineerVoice, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var waiting: CheckedContinuation<Void, Never>?
    private(set) var isSpeaking = false
    let voice: AVSpeechSynthesisVoice?

    override init() {
        let gb = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-GB" }
        voice = gb.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "en-GB")
        super.init()
        synth.delegate = self
    }

    var voiceDescription: String {
        guard let v = voice else { return "system voice" }
        let q = v.quality == .premium ? "premium" : v.quality == .enhanced ? "enhanced" : "standard"
        return "\(v.name) (\(v.language), \(q))"
    }

    func speak(_ text: String) async {
        stopSpeaking()
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = 0.52
        u.preUtteranceDelay = 0
        isSpeaking = true
        await withCheckedContinuation { c in waiting = c; synth.speak(u) }
        isSpeaking = false
    }

    func stopSpeaking() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        finish()
    }

    private func finish() { waiting?.resume(); waiting = nil }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { Task { @MainActor in self.finish() } }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { Task { @MainActor in self.finish() } }
}

/// Audio-thread side of the microphone: forwards buffers to the recogniser unless gated.
final class MicTap: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var gated = false
    private var level: Float = 0
    func set(_ r: SFSpeechAudioBufferRecognitionRequest?) { lock.withLock { request = r } }
    func setGated(_ g: Bool) { lock.withLock { gated = g } }
    var currentLevel: Float { lock.withLock { level } }
    func feed(_ buffer: AVAudioPCMBuffer) {
        var peak: Float = 0
        if let ch = buffer.floatChannelData?[0] {
            for i in stride(from: 0, to: Int(buffer.frameLength), by: 4) { peak = max(peak, abs(ch[i])) }
        }
        lock.withLock {
            level = peak
            if !gated { request?.append(buffer) }
        }
    }
}

/// The director's microphone → on-device speech recognition → whole utterances (end of speech after a pause).
/// Captured once here; the Engineer is its only consumer in V1. Gated while the Engineer talks or a take plays.
@MainActor
final class DirectorMic {
    enum Status: Equatable { case off, starting, listening, muted, unavailable(String) }
    private(set) var status: Status = .off
    var partial = ""
    var onUtterance: ((String, Date) -> Void)?
    var onPartial: ((String) -> Void)?
    /// Polled every 100 ms: true while the Engineer speaks or a take plays (half-duplex, no echo capture).
    var shouldGate: (() -> Bool)?
    var endOfSpeechPause: TimeInterval = 0.85
    private var ungateAfter: Date?

    private let engine = AVAudioEngine()
    private let tap = MicTap()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var lastChange = Date()
    private var timer: Timer?
    private var gated = false
    private var generation = 0
    var level: Float { tap.currentLevel }
    var onDevice = false

    func start(locale: Locale = Locale(identifier: "en-GB")) async {
        guard status == .off || status == .muted || { if case .unavailable = status { return true } else { return false } }() else { return }
        status = .starting
        let speechOK = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        guard status == .starting else { return }      // stopped while waiting for permission
        guard speechOK else { status = .unavailable("Speech recognition isn't allowed — System Settings › Privacy › Speech Recognition."); return }
        let micOK = await AVCaptureDevice.requestAccess(for: .audio)
        guard status == .starting else { return }
        guard micOK else { status = .unavailable("Microphone access isn't allowed — System Settings › Privacy › Microphone."); return }
        guard let r = SFSpeechRecognizer(locale: locale), r.isAvailable else { status = .unavailable("Speech recognition isn't available for \(locale.identifier)."); return }
        recognizer = r
        onDevice = r.supportsOnDeviceRecognition
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { status = .unavailable("No microphone input found."); return }
        let tap = self.tap
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in tap.feed(buffer) }
        tapInstalled = true
        do { engine.prepare(); try engine.start() } catch { status = .unavailable("Couldn't start the microphone: \(error.localizedDescription)"); return }
        beginTask()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        status = gated ? .muted : .listening
    }

    private var tapInstalled = false

    func stop() {
        timer?.invalidate(); timer = nil
        task?.cancel(); task = nil; tap.set(nil)
        // Never touch inputNode unless we installed a tap: creating it lazily while a permission prompt is
        // pending deadlocks AVAudioEngine (seen on quit, 29 Oct).
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        if engine.isRunning { engine.stop() }
        partial = ""; status = .off
    }

    /// Half-duplex: while gated nothing is recognised and any partial is discarded.
    func setGated(_ g: Bool) {
        guard g != gated else { return }
        gated = g
        tap.setGated(g)
        if g { partial = ""; onPartial?("") ; restartTask() }
        if status == .listening || status == .muted { status = g ? .muted : .listening }
    }

    private func beginTask() {
        guard let recognizer else { return }
        generation += 1
        let gen = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = true
        request.taskHint = .dictation
        tap.set(request)
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in self?.handle(text: text, final: final, failed: failed, generation: gen) }
        }
    }

    private func restartTask() {
        task?.cancel(); task = nil; tap.set(nil)
        if status != .off { beginTask() }
    }

    private func handle(text: String?, final: Bool, failed: Bool, generation gen: Int) {
        guard gen == generation, !gated else { return }
        if let text, text != partial { partial = text; lastChange = Date(); onPartial?(text) }
        if final { deliver() } else if failed, partial.isEmpty { restartTask() }
    }

    private func tick() {
        let wantGate = shouldGate?() ?? false
        if wantGate { ungateAfter = nil; setGated(true) }
        else if gated {
            if let t = ungateAfter { if Date() >= t { ungateAfter = nil; setGated(false) } }
            else { ungateAfter = Date().addingTimeInterval(0.35) }   // hangover so tails aren't heard as speech
        }
        guard !gated, !partial.isEmpty, Date().timeIntervalSince(lastChange) >= endOfSpeechPause else { return }
        deliver()
    }

    private func deliver() {
        let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        let endedAt = lastChange
        partial = ""; onPartial?("")
        restartTask()
        if !text.isEmpty { onUtterance?(text, endedAt) }
    }
}

/// Launches and owns the local Engineer language model (mlx_lm.server on loopback). Reuses one already running.
@MainActor
final class EngineerLLMServer {
    static let port = 17860
    let baseURL = URL(string: "http://127.0.0.1:\(EngineerLLMServer.port)/v1")!
    private var process: Process?
    private(set) var status = "not started"
    let projectRoot: URL

    init(projectRoot: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/CLAUDE_MAY/JUJU VO Studio")) {
        self.projectRoot = projectRoot
    }

    var python: URL { projectRoot.appendingPathComponent("Engines/engineer-llm/.venv/bin/python") }

    var modelPath: URL? {
        let hub = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cache/huggingface/hub/models--mlx-community--Qwen3-Coder-Next-4bit/snapshots")
        guard let snap = try? FileManager.default.contentsOfDirectory(at: hub, includingPropertiesForKeys: nil).first else { return nil }
        return snap
    }
    let modelName = "Qwen3-Coder-Next 4-bit (local MLX)"

    func isUp() async -> Bool {
        var r = URLRequest(url: baseURL.appendingPathComponent("models"), timeoutInterval: 1.5)
        r.httpMethod = "GET"
        guard let (_, resp) = try? await URLSession.shared.data(for: r) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    func ensureRunning() async throws {
        if await isUp() { status = "ready"; return }
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            status = "missing env"; throw NSError(domain: "JUJU", code: 1, userInfo: [NSLocalizedDescriptionKey: "Engineer LLM environment not found — run Engines/engineer-llm/setup.sh"])
        }
        guard let model = modelPath else {
            status = "missing model"; throw NSError(domain: "JUJU", code: 2, userInfo: [NSLocalizedDescriptionKey: "Qwen3-Coder-Next-4bit isn't in the Hugging Face cache"])
        }
        let p = Process()
        p.executableURL = python
        p.arguments = ["-m", "mlx_lm.server", "--model", model.path, "--host", "127.0.0.1", "--port", String(Self.port)]
        p.environment = ProcessInfo.processInfo.environment.merging(["HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1"]) { _, n in n }
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("juju-engineer-llm.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        if let h = try? FileHandle(forWritingTo: log) { p.standardOutput = h; p.standardError = h }
        status = "starting"
        try p.run()
        process = p
        for _ in 0..<120 {
            if await isUp() { status = "ready"; return }
            if !p.isRunning { status = "failed"; throw NSError(domain: "JUJU", code: 3, userInfo: [NSLocalizedDescriptionKey: "Engineer LLM server exited — see \(log.path)"]) }
            try await Task.sleep(for: .milliseconds(500))
        }
        status = "timed out"
        throw NSError(domain: "JUJU", code: 4, userInfo: [NSLocalizedDescriptionKey: "Engineer LLM server didn't start within 60 s"])
    }

    func stop() {
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        status = "stopped"
    }
}
