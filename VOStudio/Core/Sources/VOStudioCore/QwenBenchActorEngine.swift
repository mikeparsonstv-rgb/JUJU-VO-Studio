import Foundation
import RendererBenchCore
import Qwen3RendererAdapter

/// The existing, frozen Renderer Bench Qwen3-TTS 0.6B Base path (persistent worker, pinned env and weights),
/// wrapped as a JUJU actor engine. Runs from the original bench folder; writes only to the caller's output path.
public final class QwenBenchActorEngine: ActorEngine, @unchecked Sendable {
    public let benchRoot: URL
    private let adapter: Qwen3RendererAdapter
    private let queue = DispatchQueue(label: "tv.juju.vostudio.qwen", qos: .userInitiated)
    private let lock = NSLock()
    private var loaded = false

    public init(benchRoot: URL, backend: String = "mps", timeout: TimeInterval = 600) {
        self.benchRoot = benchRoot
        let python = benchRoot.appendingPathComponent(".renderer-envs/qwen3/bin/python")
        let worker = benchRoot.appendingPathComponent("Workers/Qwen3/qwen_worker.py")
        let env = ["HF_HOME": benchRoot.appendingPathComponent(".renderer-models/qwen3").path,
                   "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1", "QWEN3_DEVICE": backend,
                   "PYTORCH_ENABLE_MPS_FALLBACK": "0"]
        let client = PersistentQwenWorkerClient(pythonURL: python, workerURL: worker, timeout: timeout, environment: env)
        let available = FileManager.default.isExecutableFile(atPath: python.path) && FileManager.default.fileExists(atPath: worker.path)
        adapter = Qwen3RendererAdapter(client: client, availabilityOverride: available ? .available : .unavailable, requestedBackend: backend)
    }

    public static let defaultBenchRoot = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Documents/CODEX/JUJU VoiceOver/CuePitchBrief/TalkBack_Renderer_Bench_Brief_v0_1")

    /// Qwen3-TTS defaults from the pinned checkpoint's generation_config.json.
    static let defaults: [String: Double] = ["temperature": 0.9, "top_p": 1.0, "top_k": 50, "repetition_penalty": 1.05]

    public var descriptor: ActorEngineDescriptor {
        let d = adapter.descriptor
        return ActorEngineDescriptor(
            id: "qwen3-bench", displayName: "Qwen3-TTS 0.6B Base (Renderer Bench)", adapterVersion: d.rendererVersion,
            modelID: "Qwen/Qwen3-TTS-12Hz-0.6B-Base", modelRevision: d.modelCheckpoint ?? "unknown",
            capabilities: ActorCapabilities(voiceCloning: true, naturalLanguageDirection: false, samplingVariation: true,
                                            emphasisMarkup: "experimental", pauseMarkup: "experimental",
                                            deterministicSeed: false, speechToSpeech: false,
                                            languages: ["en", "de", "fr", "es", "it", "pt", "ru", "zh", "ja", "ko"]),
            isTestFixture: false)
    }

    public var isAvailable: Bool { adapter.descriptor.availability == .available }

    public func health() async -> EngineHealth {
        guard isAvailable else {
            return EngineHealth(status: .unavailable, message: "Renderer Bench Qwen environment not found at \(benchRoot.path)", details: [:])
        }
        let h: RendererHealth = await withCheckedContinuation { c in queue.async { c.resume(returning: self.adapter.healthCheck()) } }
        let isLoaded = lock.withLock { loaded }
        return EngineHealth(status: h.status == .healthy ? (isLoaded ? .ready : .available) : .unavailable, message: h.message, details: h.details)
    }

    public func warmUp() async throws {
        if lock.withLock({ loaded }) { return }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            queue.async {
                do { try self.adapter.load(); self.lock.withLock { self.loaded = true }; c.resume() } catch { c.resume(throwing: error) }
            }
        }
    }

    public func shutdown() async {
        await withCheckedContinuation { c in queue.async { _ = try? self.adapter.shutdown(); self.lock.withLock { self.loaded = false }; c.resume() } }
    }

    public func render(_ r: ActorRenderRequest) async throws -> ActorRenderOutput {
        var settings = Self.defaults
        var applied: [String] = []
        var unsupported: [String] = []
        switch r.direction.variation {
        case .standard: break
        case .fresh: applied.append("fresh read → new random seed, default sampling")
        case .livelier: settings["temperature"] = 1.05; settings["subtalker_temperature"] = 1.0
            applied.append("livelier → sampling temperature 1.05 (default 0.9)")
        case .steadier: settings["temperature"] = 0.7; settings["subtalker_temperature"] = 0.75
            applied.append("steadier → sampling temperature 0.7 (default 0.9)")
        }
        let (text, markup) = TextMarkup.apply(r.text, emphasis: r.direction.emphasis, pauseAfter: r.direction.pauseAfter)
        applied += markup.map { $0 + " (experimental: Qwen Base has no stress control)" }
        if !r.direction.note.isEmpty, r.direction.variation == .standard, markup.isEmpty {
            unsupported.append("“\(r.direction.note)” — Qwen3 0.6B Base cannot follow spoken-style direction; rendered a fresh read")
        }
        var rendererSettings: [String: JSONValue] = ["do_sample": .bool(true), "reference_asset_id": .string(r.referenceAssetID)]
        for (k, v) in settings { rendererSettings[k] = k == "top_k" ? .number(v.rounded()) : .number(v) }
        let request = RendererRequest(testID: "vostudio-\(r.runID.uuidString.lowercased())", script: text, language: r.languageTag,
                                      referenceAudioPaths: [r.referencePath],
                                      referenceAudioTranscripts: r.referenceTranscript.map { [$0] }, seed: r.seed,
                                      rendererSettings: rendererSettings)
        let started = Date()
        let rendered: RenderedAudio = try await withCheckedThrowingContinuation { c in
            queue.async {
                do { c.resume(returning: try self.adapter.render(request, to: r.outputURL)); self.lock.withLock { self.loaded = true } }
                catch { c.resume(throwing: error) }
            }
        }
        // Independent artifact validation (bench rule: an adapter's success claim is not enough).
        let validated = try AudioFileValidator.validateWAV(at: r.outputURL, reportedDuration: rendered.duration)
        return ActorRenderOutput(duration: validated.duration, textSent: text,
                                 settingsSent: settings.mapValues { String($0) }.merging(["seed": String(r.seed), "do_sample": "true"]) { a, _ in a },
                                 controlsApplied: applied, controlsUnsupported: unsupported,
                                 engineSeconds: Date().timeIntervalSince(started), environment: rendered.environmentSnapshot)
    }
}
