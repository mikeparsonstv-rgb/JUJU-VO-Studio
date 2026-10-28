import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct RendererRequest: Codable, Equatable, Sendable {
    public var testID: String
    public var script: String
    public var language: String
    public var directionText: String
    public var referenceAudioPaths: [String]
    public var referenceAudioTranscripts: [String]?
    public var guideAudioPath: String?
    public var seed: UInt64?
    public var targetDuration: Double?
    public var rendererSettings: [String: JSONValue]

    public init(testID: String, script: String, language: String, directionText: String = "",
                referenceAudioPaths: [String] = [], referenceAudioTranscripts: [String]? = nil,
                guideAudioPath: String? = nil,
                seed: UInt64? = nil, targetDuration: Double? = nil,
                rendererSettings: [String: JSONValue] = [:]) {
        self.testID = testID
        self.script = script
        self.language = language
        self.directionText = directionText
        self.referenceAudioPaths = referenceAudioPaths
        self.referenceAudioTranscripts = referenceAudioTranscripts
        self.guideAudioPath = guideAudioPath
        self.seed = seed
        self.targetDuration = targetDuration
        self.rendererSettings = rendererSettings
    }
}

public struct RendererCapabilities: Codable, Equatable, Sendable {
    public var textToSpeech, suppliedVoice, voiceCloning, guidePerformanceTransfer: Bool
    public var naturalLanguageDirection, structuredDirection, pronunciationControl, pauseControl: Bool
    public var speedControl, pitchControl, durationControl, streaming: Bool
    public var deterministicSeed, multilingual, local, cloud: Bool

    public init(textToSpeech: Bool = false, suppliedVoice: Bool = false,
                voiceCloning: Bool = false, guidePerformanceTransfer: Bool = false,
                naturalLanguageDirection: Bool = false, structuredDirection: Bool = false,
                pronunciationControl: Bool = false, pauseControl: Bool = false,
                speedControl: Bool = false, pitchControl: Bool = false,
                durationControl: Bool = false, streaming: Bool = false,
                deterministicSeed: Bool = false, multilingual: Bool = false,
                local: Bool = false, cloud: Bool = false) {
        self.textToSpeech = textToSpeech; self.suppliedVoice = suppliedVoice
        self.voiceCloning = voiceCloning; self.guidePerformanceTransfer = guidePerformanceTransfer
        self.naturalLanguageDirection = naturalLanguageDirection; self.structuredDirection = structuredDirection
        self.pronunciationControl = pronunciationControl; self.pauseControl = pauseControl
        self.speedControl = speedControl; self.pitchControl = pitchControl
        self.durationControl = durationControl; self.streaming = streaming
        self.deterministicSeed = deterministicSeed; self.multilingual = multilingual
        self.local = local; self.cloud = cloud
    }
}

public enum RendererLocation: String, Codable, Equatable, Sendable { case local, cloud }
public enum RendererAvailability: String, Codable, Equatable, Sendable { case available, unavailable }

public struct RendererDescriptor: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var location: RendererLocation
    public var availability: RendererAvailability
    public var rendererVersion: String
    public var modelCheckpoint: String?
    public var capabilities: RendererCapabilities
    public var isTestFixture: Bool

    public init(id: String, displayName: String, location: RendererLocation,
                availability: RendererAvailability, rendererVersion: String,
                modelCheckpoint: String? = nil, capabilities: RendererCapabilities,
                isTestFixture: Bool = false) {
        self.id = id; self.displayName = displayName; self.location = location
        self.availability = availability; self.rendererVersion = rendererVersion
        self.modelCheckpoint = modelCheckpoint; self.capabilities = capabilities
        self.isTestFixture = isTestFixture
    }
}

public enum RendererHealthStatus: String, Codable, Equatable, Sendable { case healthy, unavailable, degraded }

public struct RendererHealth: Codable, Equatable, Sendable {
    public var status: RendererHealthStatus
    public var message: String
    public var checkedAt: Date
    public var details: [String: String]
    public init(status: RendererHealthStatus, message: String, checkedAt: Date = Date(),
                details: [String: String] = [:]) {
        self.status = status; self.message = message; self.checkedAt = checkedAt; self.details = details
    }
}

public struct RendererResult: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var runID, testID, rendererID, rendererVersion: String
    public var modelCheckpoint: String?
    public var settingsSnapshot: [String: JSONValue]
    public var descriptorSnapshot: RendererDescriptor
    public var capabilitySnapshot: RendererCapabilities
    public var outputAudioPath: String?
    public var outputDuration: Double?
    public var renderStartedAt, renderCompletedAt: Date
    public var renderTime: Double
    public var firstAudioLatency, realtimeFactor: Double?
    public var success: Bool
    public var error: String?
    public var environmentSnapshot: [String: String]

    public init(schemaVersion: Int, runID: String, testID: String, rendererID: String,
                rendererVersion: String, modelCheckpoint: String?, settingsSnapshot: [String: JSONValue],
                descriptorSnapshot: RendererDescriptor, capabilitySnapshot: RendererCapabilities,
                outputAudioPath: String?, outputDuration: Double?, renderStartedAt: Date,
                renderCompletedAt: Date, renderTime: Double, firstAudioLatency: Double?,
                realtimeFactor: Double?, success: Bool, error: String?, environmentSnapshot: [String: String]) {
        self.schemaVersion = schemaVersion; self.runID = runID; self.testID = testID
        self.rendererID = rendererID; self.rendererVersion = rendererVersion
        self.modelCheckpoint = modelCheckpoint; self.settingsSnapshot = settingsSnapshot
        self.descriptorSnapshot = descriptorSnapshot; self.capabilitySnapshot = capabilitySnapshot
        self.outputAudioPath = outputAudioPath; self.outputDuration = outputDuration
        self.renderStartedAt = renderStartedAt; self.renderCompletedAt = renderCompletedAt
        self.renderTime = renderTime; self.firstAudioLatency = firstAudioLatency
        self.realtimeFactor = realtimeFactor; self.success = success; self.error = error
        self.environmentSnapshot = environmentSnapshot
    }
}

public struct RenderedAudio: Equatable, Sendable {
    public var duration: Double
    public var firstAudioLatency: Double?
    public var environmentSnapshot: [String: String]
    public init(duration: Double, firstAudioLatency: Double? = nil,
                environmentSnapshot: [String: String] = [:]) {
        self.duration = duration; self.firstAudioLatency = firstAudioLatency
        self.environmentSnapshot = environmentSnapshot
    }
}
