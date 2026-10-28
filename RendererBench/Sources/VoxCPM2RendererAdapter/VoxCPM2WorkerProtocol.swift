import Foundation
import RendererBenchCore

public enum VoxCPM2WorkerOperation: String, Codable, Sendable { case health, load, render, shutdown }

public enum VoxCPM2WorkerState: String, Codable, Equatable, Sendable {
    case starting
    case readyUnloaded = "ready_unloaded"
    case loading
    case readyLoaded = "ready_loaded"
    case rendering
    case failed
    case shuttingDown = "shutting_down"
    case stopped
}

public struct VoxCPM2WorkerRequest: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version", operation, requestID = "request_id", text, language
        case referenceAudio = "reference_audio", referenceText = "reference_text", outputAudio = "output_audio"
        case modelID = "model_id", modelRevision = "model_revision"
        case upstreamModelID = "upstream_model_id", upstreamModelRevision = "upstream_model_revision"
        case settings, seed
    }

    public var protocolVersion: Int
    public var operation: VoxCPM2WorkerOperation
    public var requestID: String
    public var text, language, referenceAudio, referenceText, outputAudio: String?
    public var modelID, modelRevision, upstreamModelID, upstreamModelRevision: String
    public var settings: [String: JSONValue]
    public var seed: UInt64?

    public init(protocolVersion: Int = VoxCPM2Constants.workerProtocolVersion,
                operation: VoxCPM2WorkerOperation, requestID: String,
                text: String? = nil, language: String? = nil,
                referenceAudio: String? = nil, referenceText: String? = nil,
                outputAudio: String? = nil,
                modelID: String = VoxCPM2Constants.modelID,
                modelRevision: String = VoxCPM2Constants.modelRevision,
                upstreamModelID: String = VoxCPM2Constants.upstreamModelID,
                upstreamModelRevision: String = VoxCPM2Constants.upstreamModelRevision,
                settings: [String: JSONValue] = [:], seed: UInt64? = nil) {
        self.protocolVersion = protocolVersion; self.operation = operation; self.requestID = requestID
        self.text = text; self.language = language; self.referenceAudio = referenceAudio
        self.referenceText = referenceText; self.outputAudio = outputAudio
        self.modelID = modelID; self.modelRevision = modelRevision
        self.upstreamModelID = upstreamModelID; self.upstreamModelRevision = upstreamModelRevision
        self.settings = settings; self.seed = seed
    }
}

public struct VoxCPM2WorkerResponse: Codable, Equatable, Sendable {
    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version", requestID = "request_id", success, error
        case outputAudio = "output_audio", sampleRate = "sample_rate", durationSeconds = "duration_seconds"
        case modelID = "model_id", modelRevision = "model_revision"
        case upstreamModelID = "upstream_model_id", upstreamModelRevision = "upstream_model_revision"
        case runtimeID = "runtime_id", runtimeRevision = "runtime_revision"
        case packageVersions = "package_versions", pythonVersion = "python_version"
        case osVersion = "os_version", machineArchitecture = "machine_architecture"
        case actualBackend = "actual_backend", metalAvailable = "metal_available"
        case workerStartupSeconds = "worker_startup_seconds", pythonImportSeconds = "python_import_seconds"
        case modelLoadSeconds = "model_load_seconds", generationSeconds = "generation_seconds"
        case peakResidentMemoryBytes = "peak_resident_memory_bytes"
        case modelAvailable = "model_available", renderAttemptable = "render_attemptable", warnings
        case workerState = "worker_state", workerSessionID = "worker_session_id"
        case workerReused = "worker_reused", modelReused = "model_reused", coldStart = "cold_start"
        case renderIndex = "render_index", cloneMode = "clone_mode", actualSettings = "actual_settings"
    }

    public var protocolVersion: Int
    public var requestID: String
    public var success: Bool
    public var error, outputAudio: String?
    public var sampleRate: Int?
    public var durationSeconds: Double?
    public var modelID, modelRevision, upstreamModelID, upstreamModelRevision: String
    public var runtimeID, runtimeRevision: String
    public var packageVersions: [String: String]
    public var pythonVersion, osVersion, machineArchitecture, actualBackend: String
    public var metalAvailable: Bool?
    public var workerStartupSeconds, pythonImportSeconds, modelLoadSeconds, generationSeconds: Double?
    public var peakResidentMemoryBytes: UInt64?
    public var modelAvailable, renderAttemptable: Bool?
    public var warnings: [String]
    public var workerState: VoxCPM2WorkerState?
    public var workerSessionID: String?
    public var workerReused, modelReused, coldStart: Bool?
    public var renderIndex: Int?
    public var cloneMode: String?
    public var actualSettings: [String: JSONValue]

    public init(protocolVersion: Int = VoxCPM2Constants.workerProtocolVersion,
                requestID: String, success: Bool, error: String? = nil,
                outputAudio: String? = nil, sampleRate: Int? = nil, durationSeconds: Double? = nil,
                modelID: String = VoxCPM2Constants.modelID,
                modelRevision: String = VoxCPM2Constants.modelRevision,
                upstreamModelID: String = VoxCPM2Constants.upstreamModelID,
                upstreamModelRevision: String = VoxCPM2Constants.upstreamModelRevision,
                runtimeID: String = VoxCPM2Constants.runtimeID,
                runtimeRevision: String = VoxCPM2Constants.runtimeRevision,
                packageVersions: [String: String] = [:], pythonVersion: String = "unknown",
                osVersion: String = "unknown", machineArchitecture: String = "unknown",
                actualBackend: String = "unknown", metalAvailable: Bool? = nil,
                workerStartupSeconds: Double? = nil, pythonImportSeconds: Double? = nil,
                modelLoadSeconds: Double? = nil, generationSeconds: Double? = nil,
                peakResidentMemoryBytes: UInt64? = nil, modelAvailable: Bool? = nil,
                renderAttemptable: Bool? = nil, warnings: [String] = [],
                workerState: VoxCPM2WorkerState? = nil, workerSessionID: String? = nil,
                workerReused: Bool? = nil, modelReused: Bool? = nil, coldStart: Bool? = nil,
                renderIndex: Int? = nil, cloneMode: String? = nil,
                actualSettings: [String: JSONValue] = [:]) {
        self.protocolVersion = protocolVersion; self.requestID = requestID; self.success = success
        self.error = error; self.outputAudio = outputAudio; self.sampleRate = sampleRate
        self.durationSeconds = durationSeconds; self.modelID = modelID; self.modelRevision = modelRevision
        self.upstreamModelID = upstreamModelID; self.upstreamModelRevision = upstreamModelRevision
        self.runtimeID = runtimeID; self.runtimeRevision = runtimeRevision
        self.packageVersions = packageVersions; self.pythonVersion = pythonVersion
        self.osVersion = osVersion; self.machineArchitecture = machineArchitecture
        self.actualBackend = actualBackend; self.metalAvailable = metalAvailable
        self.workerStartupSeconds = workerStartupSeconds; self.pythonImportSeconds = pythonImportSeconds
        self.modelLoadSeconds = modelLoadSeconds; self.generationSeconds = generationSeconds
        self.peakResidentMemoryBytes = peakResidentMemoryBytes; self.modelAvailable = modelAvailable
        self.renderAttemptable = renderAttemptable; self.warnings = warnings
        self.workerState = workerState; self.workerSessionID = workerSessionID
        self.workerReused = workerReused; self.modelReused = modelReused; self.coldStart = coldStart
        self.renderIndex = renderIndex; self.cloneMode = cloneMode; self.actualSettings = actualSettings
    }

    public var environmentSnapshot: [String: String] {
        var snapshot = [
            "renderer_adapter_version": VoxCPM2Constants.adapterVersion,
            "worker_protocol_version": String(protocolVersion),
            "voxcpm2_conversion_model_id": modelID,
            "voxcpm2_conversion_model_revision": modelRevision,
            "voxcpm2_upstream_model_id": upstreamModelID,
            "voxcpm2_upstream_model_revision": upstreamModelRevision,
            "voxcpm2_runtime_id": runtimeID,
            "voxcpm2_runtime_revision": runtimeRevision,
            "python_version": pythonVersion,
            "worker_os_version": osVersion,
            "worker_machine_architecture": machineArchitecture,
            "actual_backend": actualBackend,
            "compute_device": actualBackend
        ]
        for (key, value) in packageVersions { snapshot["package_\(key)"] = value }
        if let metalAvailable { snapshot["metal_available"] = String(metalAvailable) }
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

public enum VoxCPM2Constants {
    public static let adapterVersion = "1.0.0-rb004"
    public static let workerProtocolVersion = 1
    public static let modelID = "mlx-community/VoxCPM2-bf16"
    public static let modelRevision = "a7fb80d9056983135a54ca3f71fcc5a637ccddf5"
    public static let upstreamModelID = "openbmb/VoxCPM2"
    public static let upstreamModelRevision = "bffb3df5a29440629464e5e839f4d214c8714c3d"
    public static let upstreamSourceRevision = "616d3d3e630a9c96c2853250eef91b0f39dcd5fa"
    public static let runtimeID = "mlx-audio"
    public static let runtimeRevision = "d28d68c6ac4e28f7d2d66007f640b06cf3fd8ceb"
}
