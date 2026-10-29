import Foundation
import Observation

public struct LatencySample: Equatable, Sendable, Codable {
    public var utterance: String
    public var source: String
    /// End of the director's speech (or text submit) → interpretation ready.
    public var interpretSeconds: Double
    /// End of the director's speech → the Engineer starts speaking.
    public var firstResponseSeconds: Double
}

/// The Engineer: understands the director, operates the studio through typed actions, and only reports
/// what actually happened. Half-duplex in V1 — it doesn't listen while it speaks or while a take plays.
@MainActor @Observable
public final class Engineer {
    public enum State: String, Sendable { case disconnected, listening, interpreting, working, speaking }

    public private(set) var state: State = .disconnected
    public private(set) var log: [EngineerTurn] = []
    public private(set) var latencies: [LatencySample] = []
    public var provider: (any ConversationProvider)?
    public var providerStatus = "not configured"
    public var isConnected: Bool { state != .disconnected }

    private let studio: StudioActions
    private weak var voice: EngineerVoice?
    private let rules = RuleInterpreter()
    private var announcedRuns: Set<UUID> = []
    private var awaiting: String?

    public init(studio: StudioActions, voice: EngineerVoice?, provider: (any ConversationProvider)? = nil) {
        self.studio = studio; self.voice = voice; self.provider = provider
    }

    public func setVoice(_ v: EngineerVoice?) { voice = v }

    public func connect(greeting: String? = nil) async {
        guard state == .disconnected else { return }
        state = .listening
        log.append(.init(speaker: .system, text: "Engineer connected · \(provider?.name ?? "rules only") · local"))
        if let g = greeting { await say(g) }
    }

    public func disconnect() {
        voice?.stopSpeaking()
        state = .disconnected
        awaiting = nil
        log.append(.init(speaker: .system, text: "Engineer disconnected"))
    }

    /// One director utterance (spoken or typed). `endedAt` is when they stopped talking.
    public func hear(_ raw: String, endedAt: Date = Date()) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isConnected, !text.isEmpty else { return }
        log.append(.init(speaker: .director, text: text))
        state = .interpreting
        let ctx = studio.engineerContext

        var interpretation: Interpretation
        if awaiting == "newJobName" {
            awaiting = nil
            interpretation = Interpretation(actions: [.newJobFromSettings(name: text)], source: "follow-up")
        } else if let r = rules.interpret(text, context: ctx) {
            interpretation = r
        } else if let provider {
            do { interpretation = try await provider.interpret(text, context: ctx, history: Array(log.dropLast())) }
            catch {
                log.append(.init(speaker: .system, text: "Language model error: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"))
                interpretation = Interpretation(actions: [], reply: "Sorry, I lost that one. Say it again?", source: "error")
            }
        } else {
            interpretation = Interpretation(actions: [], reply: "I didn't catch that. Try “go for a take”, “again, livelier” or “play it back”.", source: "rules")
        }
        let interpretSeconds = Date().timeIntervalSince(endedAt)

        state = .working
        var lines: [String] = []
        var playAfter: UUID?
        for action in interpretation.actions {
            let outcome = await studio.perform(action)
            if let s = outcome.say { lines.append(s) }
            if let p = outcome.playAfterSpeaking { playAfter = p }
            if let n = outcome.needs { awaiting = n }
            if let r = outcome.queuedRunID { announcedRuns.insert(r) }
            if !outcome.ok { break }
        }
        if lines.isEmpty, let reply = interpretation.reply { lines.append(reply) }
        if lines.isEmpty { lines.append(interpretation.actions.isEmpty ? "Sorry?" : "Done.") }

        let spoken = lines.joined(separator: " ")
        latencies.append(LatencySample(utterance: text, source: interpretation.source, interpretSeconds: interpretSeconds,
                                       firstResponseSeconds: Date().timeIntervalSince(endedAt)))
        await say(spoken, latency: Date().timeIntervalSince(endedAt), source: interpretation.source)
        if let p = playAfter { studio.playTake(p) }
        if state != .disconnected { state = .listening }
    }

    /// A render finished. Returns true when the Engineer announced it and will start playback itself.
    @discardableResult
    public func renderFinished(runID: UUID, takeID: UUID?, error: String?) async -> Bool {
        guard isConnected, announcedRuns.remove(runID) != nil else { return false }
        if let takeID {
            await say("That's ready, here you go.")
            studio.playTake(takeID)
        } else {
            await say("That one didn't come through — \(Self.shorten(error ?? "the engine reported an error")).")
        }
        if state != .disconnected { state = .listening }
        return true
    }

    public func say(_ text: String, latency: Double? = nil, source: String? = nil) async {
        log.append(.init(speaker: .engineer, text: text, latency: latency))
        guard isConnected else { return }
        let previous = state
        state = .speaking
        await voice?.speak(text)
        if state == .speaking { state = previous == .speaking ? .listening : previous }
    }

    public func interruptSpeech() { voice?.stopSpeaking() }

    public var latencySummary: String {
        let v = latencies.map(\.firstResponseSeconds).sorted()
        guard !v.isEmpty else { return "no turns yet" }
        func pct(_ p: Double) -> Double { v[min(v.count - 1, Int((Double(v.count - 1) * p).rounded()))] }
        return String(format: "%d turns · response p50 %.2f s · p90 %.2f s", v.count, pct(0.5), pct(0.9))
    }

    static func shorten(_ s: String) -> String {
        let first = s.split(separator: ".").first.map(String.init) ?? s
        return String(first.prefix(90))
    }
}
