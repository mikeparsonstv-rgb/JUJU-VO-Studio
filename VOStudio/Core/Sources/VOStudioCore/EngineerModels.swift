import Foundation

/// Which script line an instruction refers to.
public enum LineRef: Equatable, Sendable, Codable {
    case current, fullRead, number(Int), next, previous, last
}

/// Which take an instruction refers to (numbers are per line and actor, as the director hears them).
public enum TakeRef: Equatable, Sendable, Codable {
    case current, latest, previous, number(Int)
}

/// Everything the Engineer can do. Each case is executed by deterministic studio code, never by the model.
public enum EngineerAction: Equatable, Sendable {
    case render(line: LineRef, actor: String?, direction: PerformanceDirection)
    case play(TakeRef)
    case stop
    case approve(TakeRef)
    case unapprove(TakeRef)
    case selectLine(LineRef)
    case selectTake(TakeRef)
    case selectActor(String)
    case cast(String)
    case export(TakeRef)
    case openJob(String)
    case listJobs
    case listVoices
    case continueJob
    case newJobFromSettings(name: String?)
    case castingSearch(String)
    case unsupported(request: String, reason: String)

    public var name: String {
        switch self {
        case .render: "render"; case .play: "play"; case .stop: "stop"; case .approve: "approve"; case .unapprove: "unapprove"
        case .selectLine: "select_line"; case .selectTake: "select_take"; case .selectActor: "select_actor"; case .cast: "cast"
        case .export: "export"; case .openJob: "open_job"; case .listJobs: "list_jobs"; case .listVoices: "list_voices"
        case .continueJob: "continue_job"; case .newJobFromSettings: "new_job_from_settings"; case .castingSearch: "casting_search"
        case .unsupported: "unsupported"
        }
    }
}

public struct ActionOutcome: Equatable, Sendable {
    public var ok: Bool
    /// Short, truthful line for the Engineer to say about what actually happened.
    public var say: String?
    public var detail: String?
    /// A render that was queued (the Engineer will announce it when it is ready).
    public var queuedRunID: UUID?
    public init(ok: Bool, say: String? = nil, detail: String? = nil, queuedRunID: UUID? = nil) {
        self.ok = ok; self.say = say; self.detail = detail; self.queuedRunID = queuedRunID
    }
}

/// Compact, factual session state for the interpreter. The model is told only what is true here.
public struct EngineerContext: Equatable, Sendable, Codable {
    public struct Line: Equatable, Sendable, Codable { public var number: Int; public var text: String }
    public struct TakeInfo: Equatable, Sendable, Codable { public var line: String; public var actor: String; public var number: Int; public var approved: Bool; public var selected: Bool }
    public var jobName: String?
    public var languageTag: String?
    public var lines: [Line] = []
    public var currentLine: String = "none"          // "Line 03" / "Full read"
    public var cast: [String] = []
    public var currentActor: String?
    public var castWithoutVoice: [String] = []
    public var takes: [TakeInfo] = []
    public var voicesInLibrary: [String] = []
    public var recentJobs: [String] = []
    public var rendering: Bool = false
    public var engine: String = ""
    public var awaitingWelcomeChoice: Bool = false
    public init() {}
}

/// What an interpreter returns for one director utterance.
public struct Interpretation: Equatable, Sendable {
    public var actions: [EngineerAction]
    /// Conversational reply when there is nothing to do (questions, clarifications).
    public var reply: String?
    public var source: String                       // "rules" | provider name
    public init(actions: [EngineerAction], reply: String? = nil, source: String) {
        self.actions = actions; self.reply = reply; self.source = source
    }
}

public protocol ConversationProvider: Sendable {
    var name: String { get }
    func interpret(_ utterance: String, context: EngineerContext, history: [EngineerTurn]) async throws -> Interpretation
}

public struct EngineerTurn: Equatable, Sendable, Codable {
    public enum Speaker: String, Sendable, Codable { case director, engineer, system }
    public var speaker: Speaker
    public var text: String
    public var at: Date
    public var latency: Double?
    public init(speaker: Speaker, text: String, at: Date = Date(), latency: Double? = nil) {
        self.speaker = speaker; self.text = text; self.at = at; self.latency = latency
    }
}

/// The studio side the Engineer operates. The app's model and the headless test studio both implement it,
/// so voice and UI share one source of truth (brief §1.1).
@MainActor
public protocol StudioActions: AnyObject {
    var engineerContext: EngineerContext { get }
    func perform(_ action: EngineerAction) async -> ActionOutcome
}

/// The Engineer's spoken output. Implementations must return only when speech has finished (or was cut).
@MainActor
public protocol EngineerVoice: AnyObject {
    func speak(_ text: String) async
    func stopSpeaking()
}
