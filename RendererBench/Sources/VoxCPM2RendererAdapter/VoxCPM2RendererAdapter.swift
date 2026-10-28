import Foundation
import RendererBenchCore

public enum VoxCPM2AdapterError: Error, LocalizedError {
    case missingReferenceAudio, missingReferenceTranscript, tooManyReferenceFiles
    case unsupportedDirection, worker(String), outputPathMismatch

    public var errorDescription: String? {
        switch self {
        case .missingReferenceAudio: "VoxCPM2 RB-004 continuation cloning requires one reference audio file"
        case .missingReferenceTranscript: "VoxCPM2 RB-004 continuation cloning requires the exact reference transcript"
        case .tooManyReferenceFiles: "VoxCPM2 RB-004 accepts exactly one reference audio file"
        case .unsupportedDirection: "VoxCPM2 style/voice-design instructions are not exposed by the RB-004 baseline adapter"
        case .worker(let reason): "VoxCPM2 worker failed: \(reason)"
        case .outputPathMismatch: "VoxCPM2 worker reported an output outside the bench-controlled run directory"
        }
    }
}

public struct VoxCPM2WorkerFailure: RendererFailureMetadata, LocalizedError {
    public let message: String
    public let environmentSnapshot: [String: String]
    public var errorDescription: String? { "VoxCPM2 worker failed: \(message)" }
}

public struct VoxCPM2RendererAdapter: RendererAdapter {
    private let client: any VoxCPM2WorkerClient
    private let availabilityOverride: RendererAvailability?

    public init(client: any VoxCPM2WorkerClient,
                availabilityOverride: RendererAvailability? = nil) {
        self.client = client; self.availabilityOverride = availabilityOverride
    }

    public var descriptor: RendererDescriptor {
        RendererDescriptor(
            id: "voxcpm2", displayName: "VoxCPM2 (MLX BF16)", location: .local,
            availability: availabilityOverride ?? .available,
            rendererVersion: VoxCPM2Constants.adapterVersion,
            modelCheckpoint: "\(VoxCPM2Constants.modelID)@\(VoxCPM2Constants.modelRevision); upstream=\(VoxCPM2Constants.upstreamModelID)@\(VoxCPM2Constants.upstreamModelRevision)",
            capabilities: RendererCapabilities(
                textToSpeech: true, suppliedVoice: true, voiceCloning: true,
                guidePerformanceTransfer: false, naturalLanguageDirection: false,
                structuredDirection: false, streaming: false, deterministicSeed: false,
                multilingual: true, local: true))
    }

    public func healthCheck() -> RendererHealth {
        let request = VoxCPM2WorkerRequest(operation: .health,
                                           requestID: UUID().uuidString.lowercased())
        do {
            let response = try client.send(request)
            let ready = response.success && response.modelAvailable == true &&
                response.renderAttemptable == true && response.metalAvailable == true
            var details = response.environmentSnapshot
            details["model_available"] = String(response.modelAvailable ?? false)
            details["render_attemptable"] = String(response.renderAttemptable ?? false)
            return RendererHealth(
                status: ready ? .healthy : .unavailable,
                message: ready ? "VoxCPM2 MLX runtime and pinned BF16 model are ready" :
                    (response.error ?? "VoxCPM2 render is unavailable"), details: details)
        } catch {
            return RendererHealth(status: .unavailable, message: error.localizedDescription,
                details: ["renderer_adapter_version": VoxCPM2Constants.adapterVersion])
        }
    }

    @discardableResult
    public func load() throws -> VoxCPM2WorkerResponse {
        let response = try client.send(VoxCPM2WorkerRequest(
            operation: .load, requestID: UUID().uuidString.lowercased()))
        guard response.success, response.workerState == .readyLoaded else {
            throw VoxCPM2WorkerFailure(message: response.error ?? "model did not reach ready_loaded",
                                       environmentSnapshot: response.environmentSnapshot)
        }
        return response
    }

    @discardableResult
    public func shutdown() throws -> VoxCPM2WorkerResponse {
        try client.send(VoxCPM2WorkerRequest(
            operation: .shutdown, requestID: UUID().uuidString.lowercased()))
    }

    public func render(_ request: RendererRequest, to outputURL: URL) throws -> RenderedAudio {
        guard request.directionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoxCPM2AdapterError.unsupportedDirection
        }
        guard !request.referenceAudioPaths.isEmpty else { throw VoxCPM2AdapterError.missingReferenceAudio }
        guard request.referenceAudioPaths.count == 1 else { throw VoxCPM2AdapterError.tooManyReferenceFiles }
        guard let referenceText = request.referenceAudioTranscripts?.first,
              !referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoxCPM2AdapterError.missingReferenceTranscript
        }
        let referenceURL = URL(fileURLWithPath: request.referenceAudioPaths[0]).standardizedFileURL
        let workerRequest = VoxCPM2WorkerRequest(
            operation: .render, requestID: UUID().uuidString.lowercased(), text: request.script,
            language: request.language, referenceAudio: referenceURL.path,
            referenceText: referenceText, outputAudio: outputURL.standardizedFileURL.path,
            settings: request.rendererSettings, seed: request.seed)
        let adapterStarted = Date()
        let response: VoxCPM2WorkerResponse
        do { response = try client.send(workerRequest) }
        catch {
            throw VoxCPM2WorkerFailure(message: error.localizedDescription,
                environmentSnapshot: ["renderer_adapter_version": VoxCPM2Constants.adapterVersion])
        }
        guard response.success else {
            throw VoxCPM2WorkerFailure(message: response.error ?? "unknown worker error",
                                       environmentSnapshot: response.environmentSnapshot)
        }
        guard let workerPath = response.outputAudio,
              URL(fileURLWithPath: workerPath).standardizedFileURL == outputURL.standardizedFileURL else {
            throw VoxCPM2AdapterError.outputPathMismatch
        }
        guard let duration = response.durationSeconds else {
            throw VoxCPM2AdapterError.worker("response omitted duration_seconds")
        }
        var environment = response.environmentSnapshot
        environment["adapter_total_seconds"] = String(Date().timeIntervalSince(adapterStarted))
        environment["reference_audio_path"] = referenceURL.path
        environment["reference_transcript_present"] = "true"
        environment["requested_language"] = request.language
        if case .string(let assetID)? = request.rendererSettings["reference_asset_id"] {
            environment["reference_asset_id"] = assetID
        }
        return RenderedAudio(duration: duration, environmentSnapshot: environment)
    }
}

public enum VoxCPM2AdapterFactory {
    public static func live(projectRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                            timeout: TimeInterval? = nil) -> VoxCPM2RendererAdapter {
        let environment = ProcessInfo.processInfo.environment
        let python = environment["VOXCPM2_WORKER_PYTHON"].map(URL.init(fileURLWithPath:)) ??
            projectRoot.appending(path: ".renderer-envs/voxcpm2/bin/python")
        let worker = environment["VOXCPM2_WORKER_SCRIPT"].map(URL.init(fileURLWithPath:)) ??
            projectRoot.appending(path: "Workers/VoxCPM2/voxcpm2_worker.py")
        let configuredTimeout = timeout ?? environment["VOXCPM2_TIMEOUT_SECONDS"].flatMap(Double.init) ?? 1_800
        let workerEnvironment = [
            "HF_HOME": environment["VOXCPM2_MODEL_HOME"] ?? projectRoot.appending(path: ".renderer-models/voxcpm2").path
        ]
        let client = PersistentVoxCPM2WorkerClient(
            pythonURL: python, workerURL: worker, timeout: configuredTimeout,
            environment: workerEnvironment)
        let available = FileManager.default.isExecutableFile(atPath: python.path) &&
            FileManager.default.fileExists(atPath: worker.path)
        return VoxCPM2RendererAdapter(client: client,
                                      availabilityOverride: available ? .available : .unavailable)
    }
}
