import Foundation
import RendererBenchCore

public enum ChatterboxWorkerOperation: String, Codable, Sendable { case health, load, render, shutdown }

public enum ChatterboxWorkerState: String, Codable, Equatable, Sendable {
    case starting
    case readyUnloaded = "ready_unloaded"
    case loading
    case readyLoaded = "ready_loaded"
    case rendering
    case failed
    case shuttingDown = "shutting_down"
    case stopped
}

public struct ChatterboxWorkerRequest: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version", operation, requestID = "request_id", text
        case languageID = "language_id", referenceAudio = "reference_audio", outputAudio = "output_audio"
        case modelID = "model_id", modelRevision = "model_revision", sourceRevision = "source_revision"
        case variant, t3Model = "t3_model", requestedBackend = "requested_backend", settings, seed
    }

    public var protocolVersion: Int
    public var operation: ChatterboxWorkerOperation
    public var requestID: String
    public var text, languageID, referenceAudio, outputAudio: String?
    public var modelID, modelRevision, sourceRevision, variant, t3Model, requestedBackend: String
    public var settings: [String: JSONValue]
    public var seed: UInt64?

    public init(protocolVersion: Int = ChatterboxConstants.workerProtocolVersion,
                operation: ChatterboxWorkerOperation, requestID: String,
                text: String? = nil, languageID: String? = nil,
                referenceAudio: String? = nil, outputAudio: String? = nil,
                modelID: String = ChatterboxConstants.modelID,
                modelRevision: String = ChatterboxConstants.modelRevision,
                sourceRevision: String = ChatterboxConstants.sourceRevision,
                variant: String = ChatterboxConstants.variant,
                t3Model: String = ChatterboxConstants.t3Model,
                requestedBackend: String = "mps",
                settings: [String: JSONValue] = [:], seed: UInt64? = nil) {
        self.protocolVersion = protocolVersion; self.operation = operation; self.requestID = requestID
        self.text = text; self.languageID = languageID; self.referenceAudio = referenceAudio
        self.outputAudio = outputAudio; self.modelID = modelID; self.modelRevision = modelRevision
        self.sourceRevision = sourceRevision; self.variant = variant; self.t3Model = t3Model
        self.requestedBackend = requestedBackend; self.settings = settings; self.seed = seed
    }
}

public struct ChatterboxWorkerResponse: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version", requestID = "request_id", success, error
        case outputAudio = "output_audio", sampleRate = "sample_rate", durationSeconds = "duration_seconds"
        case modelID = "model_id", modelRevision = "model_revision", sourceRevision = "source_revision"
        case variant, t3Model = "t3_model", t3Filename = "t3_filename"
        case runtimeID = "runtime_id", runtimeRevision = "runtime_revision"
        case packageVersions = "package_versions", pythonVersion = "python_version"
        case osVersion = "os_version", machineArchitecture = "machine_architecture"
        case requestedBackend = "requested_backend", actualBackend = "actual_backend"
        case mpsAvailable = "mps_available", mpsBuilt = "mps_built"
        case workerStartupSeconds = "worker_startup_seconds", pythonImportSeconds = "python_import_seconds"
        case modelLoadSeconds = "model_load_seconds", generationSeconds = "generation_seconds"
        case peakResidentMemoryBytes = "peak_resident_memory_bytes"
        case modelAvailable = "model_available", renderAttemptable = "render_attemptable", warnings
        case workerState = "worker_state", workerSessionID = "worker_session_id"
        case workerReused = "worker_reused", modelReused = "model_reused", coldStart = "cold_start"
        case renderIndex = "render_index", cloneMode = "clone_mode", actualSettings = "actual_settings"
        case watermarkExpected = "watermark_expected", watermarkEnabled = "watermark_enabled"
        case watermarkSystem = "watermark_system", watermarkVersion = "watermark_version"
        case referenceTranscriptUsed = "reference_transcript_used"
    }

    public var protocolVersion: Int
    public var requestID: String
    public var success: Bool
    public var error, outputAudio: String?
    public var sampleRate: Int?
    public var durationSeconds: Double?
    public var modelID, modelRevision, sourceRevision, variant, t3Model, t3Filename: String
    public var runtimeID, runtimeRevision: String
    public var packageVersions: [String: String]
    public var pythonVersion, osVersion, machineArchitecture, requestedBackend, actualBackend: String
    public var mpsAvailable, mpsBuilt: Bool?
    public var workerStartupSeconds, pythonImportSeconds, modelLoadSeconds, generationSeconds: Double?
    public var peakResidentMemoryBytes: UInt64?
    public var modelAvailable, renderAttemptable: Bool?
    public var warnings: [String]
    public var workerState: ChatterboxWorkerState?
    public var workerSessionID: String?
    public var workerReused, modelReused, coldStart: Bool?
    public var renderIndex: Int?
    public var cloneMode: String?
    public var actualSettings: [String: JSONValue]
    public var watermarkExpected, watermarkEnabled: Bool?
    public var watermarkSystem, watermarkVersion: String?
    public var referenceTranscriptUsed: Bool?

    public init(protocolVersion: Int = ChatterboxConstants.workerProtocolVersion,
                requestID: String, success: Bool, error: String? = nil,
                outputAudio: String? = nil, sampleRate: Int? = nil, durationSeconds: Double? = nil,
                modelID: String = ChatterboxConstants.modelID,
                modelRevision: String = ChatterboxConstants.modelRevision,
                sourceRevision: String = ChatterboxConstants.sourceRevision,
                variant: String = ChatterboxConstants.variant,
                t3Model: String = ChatterboxConstants.t3Model,
                t3Filename: String = ChatterboxConstants.t3Filename,
                runtimeID: String = ChatterboxConstants.runtimeID,
                runtimeRevision: String = ChatterboxConstants.runtimeRevision,
                packageVersions: [String: String] = [:], pythonVersion: String = "unknown",
                osVersion: String = "unknown", machineArchitecture: String = "unknown",
                requestedBackend: String = "mps", actualBackend: String = "unknown",
                mpsAvailable: Bool? = nil, mpsBuilt: Bool? = nil,
                workerStartupSeconds: Double? = nil, pythonImportSeconds: Double? = nil,
                modelLoadSeconds: Double? = nil, generationSeconds: Double? = nil,
                peakResidentMemoryBytes: UInt64? = nil, modelAvailable: Bool? = nil,
                renderAttemptable: Bool? = nil, warnings: [String] = [],
                workerState: ChatterboxWorkerState? = nil, workerSessionID: String? = nil,
                workerReused: Bool? = nil, modelReused: Bool? = nil, coldStart: Bool? = nil,
                renderIndex: Int? = nil, cloneMode: String? = nil,
                actualSettings: [String: JSONValue] = [:], watermarkExpected: Bool? = true,
                watermarkEnabled: Bool? = nil, watermarkSystem: String? = "PerTh implicit",
                watermarkVersion: String? = nil, referenceTranscriptUsed: Bool? = false) {
        self.protocolVersion = protocolVersion; self.requestID = requestID; self.success = success
        self.error = error; self.outputAudio = outputAudio; self.sampleRate = sampleRate
        self.durationSeconds = durationSeconds; self.modelID = modelID; self.modelRevision = modelRevision
        self.sourceRevision = sourceRevision; self.variant = variant; self.t3Model = t3Model
        self.t3Filename = t3Filename; self.runtimeID = runtimeID; self.runtimeRevision = runtimeRevision
        self.packageVersions = packageVersions; self.pythonVersion = pythonVersion
        self.osVersion = osVersion; self.machineArchitecture = machineArchitecture
        self.requestedBackend = requestedBackend; self.actualBackend = actualBackend
        self.mpsAvailable = mpsAvailable; self.mpsBuilt = mpsBuilt
        self.workerStartupSeconds = workerStartupSeconds; self.pythonImportSeconds = pythonImportSeconds
        self.modelLoadSeconds = modelLoadSeconds; self.generationSeconds = generationSeconds
        self.peakResidentMemoryBytes = peakResidentMemoryBytes; self.modelAvailable = modelAvailable
        self.renderAttemptable = renderAttemptable; self.warnings = warnings
        self.workerState = workerState; self.workerSessionID = workerSessionID
        self.workerReused = workerReused; self.modelReused = modelReused; self.coldStart = coldStart
        self.renderIndex = renderIndex; self.cloneMode = cloneMode; self.actualSettings = actualSettings
        self.watermarkExpected = watermarkExpected; self.watermarkEnabled = watermarkEnabled
        self.watermarkSystem = watermarkSystem; self.watermarkVersion = watermarkVersion
        self.referenceTranscriptUsed = referenceTranscriptUsed
    }

    public var environmentSnapshot: [String: String] {
        var snapshot = [
            "renderer_adapter_version": ChatterboxConstants.adapterVersion,
            "worker_protocol_version": String(protocolVersion),
            "chatterbox_renderer_family": "Chatterbox",
            "chatterbox_variant": variant,
            "chatterbox_source_revision": sourceRevision,
            "chatterbox_model_id": modelID,
            "chatterbox_model_revision": modelRevision,
            "chatterbox_t3_model": t3Model,
            "chatterbox_t3_filename": t3Filename,
            "chatterbox_runtime_id": runtimeID,
            "chatterbox_runtime_revision": runtimeRevision,
            "python_version": pythonVersion,
            "worker_os_version": osVersion,
            "worker_machine_architecture": machineArchitecture,
            "requested_backend": requestedBackend,
            "actual_backend": actualBackend,
            "compute_device": actualBackend
        ]
        for (key, value) in packageVersions { snapshot["package_\(key)"] = value }
        if let mpsAvailable { snapshot["mps_available"] = String(mpsAvailable) }
        if let mpsBuilt { snapshot["mps_built"] = String(mpsBuilt) }
        if let workerStartupSeconds { snapshot["worker_startup_seconds"] = String(workerStartupSeconds) }
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
        if let renderIndex { snapshot["render_index"] = String(renderIndex) }
        if let cloneMode { snapshot["clone_mode"] = cloneMode }
        if let watermarkExpected { snapshot["watermark_expected"] = String(watermarkExpected) }
        if let watermarkEnabled { snapshot["watermark_enabled"] = String(watermarkEnabled) }
        if let watermarkSystem { snapshot["watermark_system"] = watermarkSystem }
        if let watermarkVersion { snapshot["watermark_version"] = watermarkVersion }
        if let referenceTranscriptUsed { snapshot["reference_transcript_used"] = String(referenceTranscriptUsed) }
        for (key, value) in actualSettings { snapshot["actual_setting_\(key)"] = Self.string(value) }
        return snapshot
    }

    private static func string(_ value: JSONValue) -> String {
        switch value {
        case .string(let value): value
        case .number(let value): String(value)
        case .bool(let value): String(value)
        case .null: "null"
        case .array, .object: "structured"
        }
    }
}

public enum ChatterboxConstants {
    public static let adapterVersion = "1.0.0-rb005"
    public static let workerProtocolVersion = 1
    public static let modelID = "ResembleAI/chatterbox"
    public static let modelRevision = "5bb1f6ee58e50c3b8d408bc82a6d3740c2db6e18"
    public static let sourceRevision = "5de7a54aa4e5e2baadb0182dde554908b48b85c2"
    public static let variant = "Multilingual V3"
    public static let t3Model = "v3"
    public static let t3Filename = "t3_mtl23ls_v3.safetensors"
    public static let runtimeID = "chatterbox-tts"
    public static let runtimeRevision = sourceRevision
    public static let perthRevision = "ce86c49d029f42272c1902eccb675556b9ed2330"
}
