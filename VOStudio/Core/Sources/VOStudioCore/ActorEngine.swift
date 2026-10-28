import Foundation

/// Renderer-neutral performance direction. Adapters translate it only into controls the engine really has,
/// and report what they applied and what they could not (brief §5: explicit unsupported beats fake success).
public struct PerformanceDirection: Codable, Sendable, Equatable {
    public enum Variation: String, Codable, Sendable, CaseIterable {
        case standard   // engine defaults
        case fresh      // same settings, new random seed — "again"
        case livelier   // more variation in the read
        case steadier   // less variation, flatter/safer read
    }
    public var variation: Variation = .standard
    /// Words to stress ("today ONLY at our store").
    public var emphasis: [String] = []
    /// Words to leave a beat after.
    public var pauseAfter: [String] = []
    /// What the director actually said, kept verbatim.
    public var note: String = ""
    public init(variation: Variation = .standard, emphasis: [String] = [], pauseAfter: [String] = [], note: String = "") {
        self.variation = variation; self.emphasis = emphasis; self.pauseAfter = pauseAfter; self.note = note
    }
    public var isEmpty: Bool { variation == .standard && emphasis.isEmpty && pauseAfter.isEmpty && note.isEmpty }
}

public struct ActorCapabilities: Codable, Sendable, Equatable {
    public var voiceCloning: Bool
    public var naturalLanguageDirection: Bool
    public var samplingVariation: Bool
    public var emphasisMarkup: String        // "none" | "experimental" | "supported"
    public var pauseMarkup: String
    public var deterministicSeed: Bool
    public var speechToSpeech: Bool
    public var languages: [String]
}

public struct ActorEngineDescriptor: Codable, Sendable, Equatable {
    public var id: String
    public var displayName: String
    public var adapterVersion: String
    public var modelID: String
    public var modelRevision: String
    public var capabilities: ActorCapabilities
    public var isTestFixture: Bool
}

public struct EngineHealth: Sendable, Equatable {
    public enum Status: String, Sendable { case ready, available, unavailable }
    public var status: Status
    public var message: String
    public var details: [String: String]
}

public struct ActorRenderRequest: Sendable {
    public var runID: UUID
    public var text: String
    public var languageTag: String
    public var referencePath: String
    public var referenceTranscript: String?
    public var referenceAssetID: String
    public var direction: PerformanceDirection
    public var seed: UInt64
    public var outputURL: URL
}

public struct ActorRenderOutput: Sendable, Codable, Equatable {
    public var duration: Double
    public var textSent: String
    public var settingsSent: [String: String]
    public var controlsApplied: [String]
    public var controlsUnsupported: [String]
    public var engineSeconds: Double
    public var environment: [String: String]
}

public protocol ActorEngine: Sendable {
    var descriptor: ActorEngineDescriptor { get }
    func health() async -> EngineHealth
    func warmUp() async throws
    func render(_ request: ActorRenderRequest) async throws -> ActorRenderOutput
    func shutdown() async
}

/// Whole-word, case-insensitive text markup used by engines whose only performance lever is the text itself.
public enum TextMarkup {
    public static func apply(_ text: String, emphasis: [String], pauseAfter: [String]) -> (String, [String]) {
        var out = text
        var applied: [String] = []
        for w in emphasis.map({ $0.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) }) where !w.isEmpty {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: w) + "\\b"
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(out.startIndex..., in: out)
                if re.firstMatch(in: out, range: range) != nil {
                    out = re.stringByReplacingMatches(in: out, range: range, withTemplate: w.uppercased())
                    applied.append("emphasis “\(w)” → capitalised in the text sent")
                }
            }
        }
        for w in pauseAfter.map({ $0.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) }) where !w.isEmpty {
            let pattern = "\\b(" + NSRegularExpression.escapedPattern(for: w) + ")\\b[,;:]?"
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(out.startIndex..., in: out)
                if let m = re.firstMatch(in: out, range: range), let r = Range(m.range, in: out), let word = Range(m.range(at: 1), in: out) {
                    out.replaceSubrange(r, with: String(out[word]) + "...")
                    applied.append("pause after “\(w)” → ellipsis in the text sent")
                }
            }
        }
        return (out, applied)
    }
}

/// Deterministic test fixture. Never offered as a voice; outputs are labelled mock.
public struct MockActorEngine: ActorEngine {
    public var failNext: Bool = false
    public init(failNext: Bool = false) { self.failNext = failNext }
    public var descriptor: ActorEngineDescriptor {
        ActorEngineDescriptor(id: "mock", displayName: "Mock engine (test fixture)", adapterVersion: "1", modelID: "none",
                              modelRevision: "none",
                              capabilities: ActorCapabilities(voiceCloning: false, naturalLanguageDirection: false, samplingVariation: true,
                                                              emphasisMarkup: "experimental", pauseMarkup: "experimental",
                                                              deterministicSeed: true, speechToSpeech: false, languages: ["en"]),
                              isTestFixture: true)
    }
    public func health() async -> EngineHealth { EngineHealth(status: .ready, message: "mock ready", details: [:]) }
    public func warmUp() async throws {}
    public func shutdown() async {}
    public func render(_ r: ActorRenderRequest) async throws -> ActorRenderOutput {
        if failNext { throw LibraryError.audioUnreadable("mock engine failure (requested by test)") }
        let (text, applied) = TextMarkup.apply(r.text, emphasis: r.direction.emphasis, pauseAfter: r.direction.pauseAfter)
        let seconds = max(0.3, Double(text.count) * 0.06)
        try MockTone.wav(seconds: seconds, frequency: 200 + Double(r.seed % 200)).write(to: r.outputURL)
        return ActorRenderOutput(duration: seconds, textSent: text, settingsSent: ["variation": r.direction.variation.rawValue],
                                 controlsApplied: applied, controlsUnsupported: [], engineSeconds: 0.01, environment: ["engine": "mock"])
    }
}
