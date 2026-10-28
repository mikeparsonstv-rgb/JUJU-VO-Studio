import Foundation
import RendererBenchCore

public enum Qwen3AdapterError: Error, LocalizedError {
    case missingReferenceAudio
    case tooManyReferenceFiles
    case unsupportedDirection
    case worker(String)
    case outputPathMismatch

    public var errorDescription: String? {
        switch self {
        case .missingReferenceAudio: "Qwen3 Base voice cloning requires --reference-audio"
        case .tooManyReferenceFiles: "RB-002 Qwen integration accepts exactly one reference audio file"
        case .unsupportedDirection: "Qwen3 0.6B Base does not expose natural-language performance direction in RB-002"
        case .worker(let reason): "Qwen worker failed: \(reason)"
        case .outputPathMismatch: "Qwen worker reported an output path outside the bench-controlled run directory"
        }
    }
}

public struct Qwen3WorkerFailure: RendererFailureMetadata, LocalizedError {
    public let message: String
    public let environmentSnapshot: [String: String]
    public var errorDescription: String? { "Qwen worker failed: \(message)" }
}

public struct Qwen3RendererAdapter: RendererAdapter {
    private let client: any QwenWorkerClient
    private let availabilityOverride: RendererAvailability?
    public let requestedBackend: String

    public init(client: any QwenWorkerClient, availabilityOverride: RendererAvailability? = nil,
                requestedBackend: String = "auto") {
        self.client = client; self.availabilityOverride = availabilityOverride
        self.requestedBackend = requestedBackend
    }

    public var descriptor: RendererDescriptor {
        RendererDescriptor(
            id: "qwen3", displayName: "Qwen3-TTS 12Hz 0.6B Base", location: .local,
            availability: availabilityOverride ?? .available,
            rendererVersion: Qwen3Constants.adapterVersion,
            modelCheckpoint: "\(Qwen3Constants.modelID)@\(Qwen3Constants.modelRevision)",
            capabilities: RendererCapabilities(
                textToSpeech: true, suppliedVoice: true, voiceCloning: true,
                naturalLanguageDirection: false, streaming: false,
                deterministicSeed: false, multilingual: true, local: true))
    }

    public func healthCheck() -> RendererHealth {
        let request = QwenWorkerRequest(operation: .health, requestID: UUID().uuidString.lowercased(),
                                        requestedBackend: requestedBackend)
        do {
            let response = try client.send(request)
            let ready = response.success && response.modelAvailable == true && response.tokenizerAvailable == true
            var details = response.environmentSnapshot
            details["model_available"] = String(response.modelAvailable ?? false)
            details["tokenizer_available"] = String(response.tokenizerAvailable ?? false)
            details["render_attemptable"] = String(response.renderAttemptable ?? false)
            return RendererHealth(status: ready ? .healthy : .unavailable,
                                  message: ready ? "Qwen worker and pinned model assets are ready" : (response.error ?? "Qwen render is unavailable"),
                                  details: details)
        } catch {
            return RendererHealth(status: .unavailable, message: error.localizedDescription,
                                  details: ["renderer_adapter_version": Qwen3Constants.adapterVersion])
        }
    }

    @discardableResult
    public func load() throws -> QwenWorkerResponse {
        let request = QwenWorkerRequest(operation: .load, requestID: UUID().uuidString.lowercased(),
                                        requestedBackend: requestedBackend)
        let response = try client.send(request)
        guard response.success, response.workerState == .readyLoaded else {
            throw Qwen3WorkerFailure(message: response.error ?? "model did not reach ready_loaded",
                                     environmentSnapshot: response.environmentSnapshot)
        }
        return response
    }

    @discardableResult
    public func shutdown() throws -> QwenWorkerResponse {
        let request = QwenWorkerRequest(operation: .shutdown, requestID: UUID().uuidString.lowercased(),
                                        requestedBackend: requestedBackend)
        return try client.send(request)
    }

    public func render(_ request: RendererRequest, to outputURL: URL) throws -> RenderedAudio {
        guard request.directionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Qwen3AdapterError.unsupportedDirection
        }
        guard !request.referenceAudioPaths.isEmpty else { throw Qwen3AdapterError.missingReferenceAudio }
        guard request.referenceAudioPaths.count == 1 else { throw Qwen3AdapterError.tooManyReferenceFiles }
        let referenceURL = URL(fileURLWithPath: request.referenceAudioPaths[0]).standardizedFileURL
        let referenceText = request.referenceAudioTranscripts?.first
        let workerRequest = QwenWorkerRequest(
            operation: .render, requestID: UUID().uuidString.lowercased(), text: request.script,
            language: Self.qwenLanguage(from: request.language), referenceAudio: referenceURL.path,
            referenceText: referenceText, outputAudio: outputURL.standardizedFileURL.path,
            seed: request.seed, settings: request.rendererSettings, requestedBackend: requestedBackend)
        let adapterStarted = Date()
        let response: QwenWorkerResponse
        do { response = try client.send(workerRequest) }
        catch {
            throw Qwen3WorkerFailure(message: error.localizedDescription,
                                     environmentSnapshot: ["renderer_adapter_version": Qwen3Constants.adapterVersion])
        }
        guard response.success else {
            throw Qwen3WorkerFailure(message: response.error ?? "unknown worker error",
                                     environmentSnapshot: response.environmentSnapshot)
        }
        guard let workerPath = response.outputAudio,
              URL(fileURLWithPath: workerPath).standardizedFileURL == outputURL.standardizedFileURL else {
            throw Qwen3AdapterError.outputPathMismatch
        }
        guard let duration = response.durationSeconds else {
            throw Qwen3AdapterError.worker("response omitted duration_seconds")
        }
        var environment = response.environmentSnapshot
        environment["adapter_total_seconds"] = String(Date().timeIntervalSince(adapterStarted))
        environment["reference_audio_path"] = referenceURL.path
        environment["reference_transcript_present"] = String(!(referenceText ?? "").isEmpty)
        if case .string(let assetID)? = request.rendererSettings["reference_asset_id"] {
            environment["reference_asset_id"] = assetID
        }
        environment["qwen_language"] = workerRequest.language ?? "Auto"
        return RenderedAudio(duration: duration, environmentSnapshot: environment)
    }

    private static func qwenLanguage(from tag: String) -> String {
        let primary = tag.lowercased().split(separator: "-").first.map(String.init) ?? tag.lowercased()
        return ["zh": "Chinese", "en": "English", "ja": "Japanese", "ko": "Korean",
                "de": "German", "fr": "French", "ru": "Russian", "pt": "Portuguese",
                "es": "Spanish", "it": "Italian"][primary] ?? "Auto"
    }
}

public enum Qwen3AdapterFactory {
    public static func live(projectRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> Qwen3RendererAdapter {
        let environment = ProcessInfo.processInfo.environment
        let python = environment["QWEN3_WORKER_PYTHON"].map(URL.init(fileURLWithPath:)) ??
            projectRoot.appending(path: ".renderer-envs/qwen3/bin/python")
        let worker = environment["QWEN3_WORKER_SCRIPT"].map(URL.init(fileURLWithPath:)) ??
            projectRoot.appending(path: "Workers/Qwen3/qwen_worker.py")
        let timeout = environment["QWEN3_TIMEOUT_SECONDS"].flatMap(Double.init) ?? 900
        let workerEnvironment = [
            "HF_HOME": environment["QWEN3_MODEL_HOME"] ?? projectRoot.appending(path: ".renderer-models/qwen3").path,
            "QWEN3_DEVICE": environment["QWEN3_DEVICE"] ?? "auto"
        ]
        let backend = environment["QWEN3_DEVICE"] ?? "auto"
        let client = PersistentQwenWorkerClient(pythonURL: python, workerURL: worker,
                                                timeout: timeout, environment: workerEnvironment)
        let available = FileManager.default.isExecutableFile(atPath: python.path) &&
            FileManager.default.fileExists(atPath: worker.path)
        return Qwen3RendererAdapter(client: client, availabilityOverride: available ? .available : .unavailable,
                                    requestedBackend: backend)
    }

    public static func persistent(projectRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                                  backend: String, timeout: TimeInterval = 900) -> Qwen3RendererAdapter {
        let environment = ProcessInfo.processInfo.environment
        let python = environment["QWEN3_WORKER_PYTHON"].map(URL.init(fileURLWithPath:)) ??
            projectRoot.appending(path: ".renderer-envs/qwen3/bin/python")
        let worker = environment["QWEN3_WORKER_SCRIPT"].map(URL.init(fileURLWithPath:)) ??
            projectRoot.appending(path: "Workers/Qwen3/qwen_worker.py")
        let workerEnvironment = [
            "HF_HOME": environment["QWEN3_MODEL_HOME"] ?? projectRoot.appending(path: ".renderer-models/qwen3").path,
            "QWEN3_DEVICE": backend
        ]
        let client = PersistentQwenWorkerClient(pythonURL: python, workerURL: worker,
                                                timeout: timeout, environment: workerEnvironment)
        let available = FileManager.default.isExecutableFile(atPath: python.path) &&
            FileManager.default.fileExists(atPath: worker.path)
        return Qwen3RendererAdapter(client: client, availabilityOverride: available ? .available : .unavailable,
                                    requestedBackend: backend)
    }
}
