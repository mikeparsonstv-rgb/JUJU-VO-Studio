import Foundation
import RendererBenchCore

public enum QwenWorkerOperation: String, Codable, Sendable { case health, load, render, shutdown }

public enum QwenWorkerState: String, Codable, Equatable, Sendable {
    case starting
    case readyUnloaded = "ready_unloaded"
    case loading
    case readyLoaded = "ready_loaded"
    case rendering
    case failed
    case shuttingDown = "shutting_down"
    case stopped
}

public struct QwenWorkerRequest: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version", operation, requestID = "request_id", text, language
        case referenceAudio = "reference_audio", referenceText = "reference_text", outputAudio = "output_audio"
        case modelID = "model_id", modelRevision = "model_revision"
        case tokenizerID = "tokenizer_id", tokenizerRevision = "tokenizer_revision", seed, settings
        case requestedBackend = "requested_backend"
    }
    public var protocolVersion: Int
    public var operation: QwenWorkerOperation
    public var requestID: String
    public var text: String?
    public var language: String?
    public var referenceAudio: String?
    public var referenceText: String?
    public var outputAudio: String?
    public var modelID: String
    public var modelRevision: String
    public var tokenizerID: String
    public var tokenizerRevision: String
    public var seed: UInt64?
    public var settings: [String: JSONValue]
    public var requestedBackend: String

    public init(protocolVersion: Int = 1, operation: QwenWorkerOperation, requestID: String,
                text: String? = nil, language: String? = nil, referenceAudio: String? = nil,
                referenceText: String? = nil, outputAudio: String? = nil,
                modelID: String = Qwen3Constants.modelID,
                modelRevision: String = Qwen3Constants.modelRevision,
                tokenizerID: String = Qwen3Constants.tokenizerID,
                tokenizerRevision: String = Qwen3Constants.tokenizerRevision,
                seed: UInt64? = nil, settings: [String: JSONValue] = [:],
                requestedBackend: String = "auto") {
        self.protocolVersion = protocolVersion; self.operation = operation; self.requestID = requestID
        self.text = text; self.language = language; self.referenceAudio = referenceAudio
        self.referenceText = referenceText; self.outputAudio = outputAudio
        self.modelID = modelID; self.modelRevision = modelRevision
        self.tokenizerID = tokenizerID; self.tokenizerRevision = tokenizerRevision
        self.seed = seed; self.settings = settings; self.requestedBackend = requestedBackend
    }
}

public struct QwenWorkerResponse: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version", requestID = "request_id", success, error
        case outputAudio = "output_audio", sampleRate = "sample_rate", durationSeconds = "duration_seconds"
        case modelID = "model_id", modelRevision = "model_revision"
        case tokenizerID = "tokenizer_id", tokenizerRevision = "tokenizer_revision"
        case packageVersions = "package_versions", pythonVersion = "python_version", osVersion = "os_version"
        case machineArchitecture = "machine_architecture", device
        case workerStartupSeconds = "worker_startup_seconds"
        case dependencyImportSeconds = "dependency_import_seconds", modelLoadSeconds = "model_load_seconds"
        case generationSeconds = "generation_seconds", peakResidentMemoryBytes = "peak_resident_memory_bytes"
        case modelAvailable = "model_available", tokenizerAvailable = "tokenizer_available"
        case renderAttemptable = "render_attemptable", warnings
        case workerState = "worker_state", workerSessionID = "worker_session_id"
        case workerReused = "worker_reused", modelReused = "model_reused", coldStart = "cold_start"
        case requestedBackend = "requested_backend", actualBackend = "actual_backend"
        case pythonImportSeconds = "python_import_seconds", renderIndex = "render_index"
        case referencePromptReused = "reference_prompt_reused"
    }
    public var protocolVersion: Int
    public var requestID: String
    public var success: Bool
    public var error: String?
    public var outputAudio: String?
    public var sampleRate: Int?
    public var durationSeconds: Double?
    public var modelID: String
    public var modelRevision: String
    public var tokenizerID: String
    public var tokenizerRevision: String
    public var packageVersions: [String: String]
    public var pythonVersion: String
    public var osVersion: String
    public var machineArchitecture: String
    public var device: String
    public var workerStartupSeconds: Double?
    public var dependencyImportSeconds: Double?
    public var modelLoadSeconds: Double?
    public var generationSeconds: Double?
    public var peakResidentMemoryBytes: UInt64?
    public var modelAvailable: Bool?
    public var tokenizerAvailable: Bool?
    public var renderAttemptable: Bool?
    public var warnings: [String]
    public var workerState: QwenWorkerState?
    public var workerSessionID: String?
    public var workerReused: Bool?
    public var modelReused: Bool?
    public var coldStart: Bool?
    public var requestedBackend: String?
    public var actualBackend: String?
    public var pythonImportSeconds: Double?
    public var renderIndex: Int?
    public var referencePromptReused: Bool?

    public init(protocolVersion: Int = 1, requestID: String, success: Bool, error: String? = nil,
                outputAudio: String? = nil, sampleRate: Int? = nil, durationSeconds: Double? = nil,
                modelID: String = Qwen3Constants.modelID,
                modelRevision: String = Qwen3Constants.modelRevision,
                tokenizerID: String = Qwen3Constants.tokenizerID,
                tokenizerRevision: String = Qwen3Constants.tokenizerRevision,
                packageVersions: [String: String] = [:], pythonVersion: String = "unknown",
                osVersion: String = "unknown", machineArchitecture: String = "unknown",
                device: String = "unknown", workerStartupSeconds: Double? = nil,
                dependencyImportSeconds: Double? = nil,
                modelLoadSeconds: Double? = nil, generationSeconds: Double? = nil,
                peakResidentMemoryBytes: UInt64? = nil,
                modelAvailable: Bool? = nil, tokenizerAvailable: Bool? = nil,
                renderAttemptable: Bool? = nil, warnings: [String] = [],
                workerState: QwenWorkerState? = nil, workerSessionID: String? = nil,
                workerReused: Bool? = nil, modelReused: Bool? = nil, coldStart: Bool? = nil,
                requestedBackend: String? = nil, actualBackend: String? = nil,
                pythonImportSeconds: Double? = nil, renderIndex: Int? = nil,
                referencePromptReused: Bool? = nil) {
        self.protocolVersion = protocolVersion; self.requestID = requestID; self.success = success
        self.error = error; self.outputAudio = outputAudio; self.sampleRate = sampleRate
        self.durationSeconds = durationSeconds; self.modelID = modelID; self.modelRevision = modelRevision
        self.tokenizerID = tokenizerID; self.tokenizerRevision = tokenizerRevision
        self.packageVersions = packageVersions; self.pythonVersion = pythonVersion
        self.osVersion = osVersion; self.machineArchitecture = machineArchitecture; self.device = device
        self.workerStartupSeconds = workerStartupSeconds
        self.dependencyImportSeconds = dependencyImportSeconds; self.modelLoadSeconds = modelLoadSeconds
        self.generationSeconds = generationSeconds; self.modelAvailable = modelAvailable
        self.peakResidentMemoryBytes = peakResidentMemoryBytes
        self.tokenizerAvailable = tokenizerAvailable; self.renderAttemptable = renderAttemptable
        self.warnings = warnings
        self.workerState = workerState; self.workerSessionID = workerSessionID
        self.workerReused = workerReused; self.modelReused = modelReused; self.coldStart = coldStart
        self.requestedBackend = requestedBackend; self.actualBackend = actualBackend
        self.pythonImportSeconds = pythonImportSeconds; self.renderIndex = renderIndex
        self.referencePromptReused = referencePromptReused
    }

    public var environmentSnapshot: [String: String] {
        var snapshot = [
            "renderer_adapter_version": Qwen3Constants.adapterVersion,
            "worker_protocol_version": String(protocolVersion),
            "qwen_model_id": modelID,
            "qwen_model_revision": modelRevision,
            "qwen_tokenizer_id": tokenizerID,
            "qwen_tokenizer_revision": tokenizerRevision,
            "python_version": pythonVersion,
            "worker_os_version": osVersion,
            "worker_machine_architecture": machineArchitecture,
            "compute_device": device
        ]
        for (key, value) in packageVersions { snapshot["package_\(key)"] = value }
        if let workerStartupSeconds { snapshot["worker_startup_seconds"] = String(workerStartupSeconds) }
        if let dependencyImportSeconds { snapshot["dependency_import_seconds"] = String(dependencyImportSeconds) }
        if let pythonImportSeconds { snapshot["python_import_seconds"] = String(pythonImportSeconds) }
        if let modelLoadSeconds { snapshot["model_load_seconds"] = String(modelLoadSeconds) }
        if let generationSeconds { snapshot["generation_seconds"] = String(generationSeconds) }
        if let peakResidentMemoryBytes { snapshot["peak_resident_memory_bytes"] = String(peakResidentMemoryBytes) }
        if let sampleRate { snapshot["worker_reported_sample_rate"] = String(sampleRate) }
        if !warnings.isEmpty { snapshot["worker_warnings"] = warnings.joined(separator: " | ") }
        if let workerState { snapshot["worker_state"] = workerState.rawValue }
        if let workerSessionID { snapshot["worker_session_id"] = workerSessionID }
        if let workerReused { snapshot["worker_reused"] = String(workerReused) }
        if let modelReused { snapshot["model_reused"] = String(modelReused) }
        if let coldStart { snapshot["cold_start"] = String(coldStart) }
        if let requestedBackend { snapshot["requested_backend"] = requestedBackend }
        if let actualBackend { snapshot["actual_backend"] = actualBackend }
        if let renderIndex { snapshot["render_index"] = String(renderIndex) }
        if let referencePromptReused { snapshot["reference_prompt_reused"] = String(referencePromptReused) }
        return snapshot
    }
}

public enum Qwen3Constants {
    public static let adapterVersion = "1.1.0-rb003"
    public static let workerProtocolVersion = 1
    public static let modelID = "Qwen/Qwen3-TTS-12Hz-0.6B-Base"
    public static let modelRevision = "5d83992436eae1d760afd27aff78a71d676296fc"
    public static let tokenizerID = "Qwen/Qwen3-TTS-Tokenizer-12Hz"
    public static let tokenizerRevision = "7dd38ad4e9bad454aae9cd937d0cd577604fe229"
}
