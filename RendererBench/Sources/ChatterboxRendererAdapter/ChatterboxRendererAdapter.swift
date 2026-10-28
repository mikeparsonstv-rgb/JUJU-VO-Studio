import Foundation
import RendererBenchCore

public enum ChatterboxAdapterError: Error, LocalizedError {
    case missingReferenceAudio, tooManyReferenceFiles
    case unsupportedDirection, worker(String), outputPathMismatch

    public var errorDescription: String? {
        switch self {
        case .missingReferenceAudio: "Chatterbox Multilingual V3 cloning requires one reference audio file"
        case .tooManyReferenceFiles: "Chatterbox Multilingual V3 accepts exactly one reference audio file"
        case .unsupportedDirection: "Generic direction is not mapped to Chatterbox native controls by the RB-005 baseline adapter"
        case .worker(let reason): "Chatterbox worker failed: \(reason)"
        case .outputPathMismatch: "Chatterbox worker reported an output outside the bench-controlled run directory"
        }
    }
}

public struct ChatterboxWorkerFailure: RendererFailureMetadata, LocalizedError {
    public let message: String
    public let environmentSnapshot: [String: String]
    public var errorDescription: String? { "Chatterbox worker failed: \(message)" }
}

public struct ChatterboxRendererAdapter: RendererAdapter {
    private let client: any ChatterboxWorkerClient
    private let availabilityOverride: RendererAvailability?

    public init(client: any ChatterboxWorkerClient,
                availabilityOverride: RendererAvailability? = nil) {
        self.client = client; self.availabilityOverride = availabilityOverride
    }

    public var descriptor: RendererDescriptor {
        RendererDescriptor(
            id: "chatterbox", displayName: "Chatterbox Multilingual V3", location: .local,
            availability: availabilityOverride ?? .available,
            rendererVersion: ChatterboxConstants.adapterVersion,
            modelCheckpoint: "\(ChatterboxConstants.modelID)@\(ChatterboxConstants.modelRevision); t3=\(ChatterboxConstants.t3Filename); source=\(ChatterboxConstants.sourceRevision)",
            capabilities: RendererCapabilities(
                textToSpeech: true, suppliedVoice: true, voiceCloning: true,
                guidePerformanceTransfer: false, naturalLanguageDirection: false,
                structuredDirection: false, streaming: false, deterministicSeed: false,
                multilingual: true, local: true))
    }

    public func healthCheck() -> RendererHealth {
        let request = ChatterboxWorkerRequest(operation: .health,
                                           requestID: UUID().uuidString.lowercased())
        do {
            let response = try client.send(request)
            let ready = response.success && response.modelAvailable == true &&
                response.renderAttemptable == true && response.mpsAvailable == true &&
                response.actualBackend == "mps" && response.variant == ChatterboxConstants.variant &&
                response.t3Model == ChatterboxConstants.t3Model
            var details = response.environmentSnapshot
            details["model_available"] = String(response.modelAvailable ?? false)
            details["render_attemptable"] = String(response.renderAttemptable ?? false)
            return RendererHealth(
                status: ready ? .healthy : .unavailable,
                message: ready ? "Chatterbox Multilingual V3 is ready on PyTorch MPS" :
                    (response.error ?? "Chatterbox render is unavailable"), details: details)
        } catch {
            return RendererHealth(status: .unavailable, message: error.localizedDescription,
                details: ["renderer_adapter_version": ChatterboxConstants.adapterVersion])
        }
    }

    @discardableResult
    public func load() throws -> ChatterboxWorkerResponse {
        let response = try client.send(ChatterboxWorkerRequest(
            operation: .load, requestID: UUID().uuidString.lowercased()))
        guard response.success, response.workerState == .readyLoaded else {
            throw ChatterboxWorkerFailure(message: response.error ?? "model did not reach ready_loaded",
                                       environmentSnapshot: response.environmentSnapshot)
        }
        return response
    }

    @discardableResult
    public func shutdown() throws -> ChatterboxWorkerResponse {
        try client.send(ChatterboxWorkerRequest(
            operation: .shutdown, requestID: UUID().uuidString.lowercased()))
    }

    public func render(_ request: RendererRequest, to outputURL: URL) throws -> RenderedAudio {
        guard request.directionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatterboxAdapterError.unsupportedDirection
        }
        guard !request.referenceAudioPaths.isEmpty else { throw ChatterboxAdapterError.missingReferenceAudio }
        guard request.referenceAudioPaths.count == 1 else { throw ChatterboxAdapterError.tooManyReferenceFiles }
        let referenceURL = URL(fileURLWithPath: request.referenceAudioPaths[0]).standardizedFileURL
        let workerRequest = ChatterboxWorkerRequest(
            operation: .render, requestID: UUID().uuidString.lowercased(), text: request.script,
            languageID: request.language, referenceAudio: referenceURL.path,
            outputAudio: outputURL.standardizedFileURL.path,
            settings: request.rendererSettings, seed: request.seed)
        let adapterStarted = Date()
        let response: ChatterboxWorkerResponse
        do { response = try client.send(workerRequest) }
        catch {
            throw ChatterboxWorkerFailure(message: error.localizedDescription,
                environmentSnapshot: ["renderer_adapter_version": ChatterboxConstants.adapterVersion])
        }
        guard response.success else {
            throw ChatterboxWorkerFailure(message: response.error ?? "unknown worker error",
                                       environmentSnapshot: response.environmentSnapshot)
        }
        guard let workerPath = response.outputAudio,
              URL(fileURLWithPath: workerPath).standardizedFileURL == outputURL.standardizedFileURL else {
            throw ChatterboxAdapterError.outputPathMismatch
        }
        guard let duration = response.durationSeconds else {
            throw ChatterboxAdapterError.worker("response omitted duration_seconds")
        }
        var environment = response.environmentSnapshot
        environment["adapter_total_seconds"] = String(Date().timeIntervalSince(adapterStarted))
        environment["reference_audio_path"] = referenceURL.path
        let transcriptAvailable = request.referenceAudioTranscripts?.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        environment["reference_transcript_available"] = String(transcriptAvailable)
        environment["reference_transcript_used"] = "false"
        environment["requested_language"] = request.language
        if case .string(let assetID)? = request.rendererSettings["reference_asset_id"] {
            environment["reference_asset_id"] = assetID
        }
        return RenderedAudio(duration: duration, environmentSnapshot: environment)
    }
}

public enum ChatterboxAdapterFactory {
    public static func live(projectRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                            timeout: TimeInterval? = nil) -> ChatterboxRendererAdapter {
        let environment = ProcessInfo.processInfo.environment
        let python = environment["CHATTERBOX_WORKER_PYTHON"].map(URL.init(fileURLWithPath:)) ??
            projectRoot.appending(path: ".renderer-envs/chatterbox/bin/python")
        let worker = environment["CHATTERBOX_WORKER_SCRIPT"].map(URL.init(fileURLWithPath:)) ??
            projectRoot.appending(path: "Workers/Chatterbox/chatterbox_worker.py")
        let configuredTimeout = timeout ?? environment["CHATTERBOX_TIMEOUT_SECONDS"].flatMap(Double.init) ?? 1_800
        let workerEnvironment = [
            "HF_HOME": environment["CHATTERBOX_MODEL_HOME"] ?? projectRoot.appending(path: ".renderer-models/chatterbox").path,
            "PKUSEG_HOME": environment["CHATTERBOX_PKUSEG_HOME"] ?? projectRoot.appending(path: ".renderer-models/chatterbox/pkuseg").path,
            "CHATTERBOX_DEVICE": environment["CHATTERBOX_DEVICE"] ?? "mps"
        ]
        let client = PersistentChatterboxWorkerClient(
            pythonURL: python, workerURL: worker, timeout: configuredTimeout,
            environment: workerEnvironment)
        let available = FileManager.default.isExecutableFile(atPath: python.path) &&
            FileManager.default.fileExists(atPath: worker.path)
        return ChatterboxRendererAdapter(client: client,
                                      availabilityOverride: available ? .available : .unavailable)
    }
}
