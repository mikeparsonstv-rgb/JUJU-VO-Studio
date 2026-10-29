import Foundation

/// Conversational interpreter over any OpenAI-compatible chat endpoint (local mlx_lm.server, LM Studio,
/// Ollama, or a cloud service). The model only *chooses* typed actions; studio code performs them and
/// the Engineer's acknowledgements come from what actually happened.
public struct OpenAICompatibleProvider: ConversationProvider {
    public var name: String
    public var baseURL: URL
    public var model: String
    public var timeout: TimeInterval
    public var apiKey: String?

    public init(name: String = "local LLM", baseURL: URL, model: String = "default_model", timeout: TimeInterval = 20, apiKey: String? = nil) {
        self.name = name; self.baseURL = baseURL; self.model = model; self.timeout = timeout; self.apiKey = apiKey
    }

    public enum ProviderError: Error, LocalizedError {
        case http(Int, String), noContent, unparseable(String)
        public var errorDescription: String? {
            switch self {
            case .http(let c, let b): "The Engineer's language model returned HTTP \(c): \(b.prefix(200))"
            case .noContent: "The Engineer's language model returned nothing."
            case .unparseable(let t): "The Engineer's language model reply wasn't understood: \(t.prefix(200))"
            }
        }
    }

    public func interpret(_ utterance: String, context: EngineerContext, history: [EngineerTurn]) async throws -> Interpretation {
        var messages: [[String: String]] = [["role": "system", "content": EngineerPrompt.system]]
        messages.append(contentsOf: EngineerPrompt.examples)
        for t in history.suffix(6) where t.speaker != .system {
            messages.append(["role": t.speaker == .director ? "user" : "assistant",
                             "content": t.speaker == .director ? "Director: \(t.text)" : "{\"say\":\(EngineerPrompt.jsonString(t.text)),\"actions\":[]}"])
        }
        messages.append(["role": "user", "content": "STUDIO STATE:\n\(EngineerPrompt.describe(context))\n\nDirector: \(utterance)"])
        let body: [String: Any] = ["model": model, "messages": messages, "temperature": 0.1, "max_tokens": 200, "stream": false]
        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"), timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ProviderError.http(code, String(decoding: data, as: UTF8.self)) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (obj["choices"] as? [[String: Any]])?.first,
              let content = (choice["message"] as? [String: Any])?["content"] as? String else { throw ProviderError.noContent }
        return try EngineerPrompt.parse(content, source: name)
    }
}

/// The contract given to the model, and a tolerant parser for what comes back.
public enum EngineerPrompt {
    public static let system = """
    You are the Engineer in a professional voice-over recording session for TV commercials. The Director talks to you; \
    an AI voice (the Actor) performs the script. You operate the studio by choosing ACTIONS. You never invent jobs, \
    voices, takes or abilities that are not in STUDIO STATE.

    Reply with ONE JSON object and nothing else:
    {"say": "<what you say aloud, max 15 words, or empty>", "actions": [<zero or more actions>]}

    Actions (use exactly these shapes):
    {"type":"render","line":"current|full|next|previous|last|<number>","actor":null|"<cast name>","variation":"standard|fresh|livelier|steadier","emphasis":["word"],"pause_after":["word"]}
    {"type":"play","take":"current|latest|previous|<number>"}
    {"type":"stop"}
    {"type":"approve","take":"current|latest|previous|<number>"}
    {"type":"unapprove","take":"current|latest|previous|<number>"}
    {"type":"select_line","line":"current|full|next|previous|last|<number>"}
    {"type":"select_take","take":"current|latest|previous|<number>"}
    {"type":"select_actor","name":"<cast name>"}
    {"type":"cast","name":"<voice in library>"}
    {"type":"casting_search","brief":"<what the director wants, in their words>"}
    {"type":"export","take":"current|latest|previous|<number>"}
    {"type":"open_job","name":"<job name>"}
    {"type":"list_jobs"} {"type":"list_voices"}
    {"type":"continue_job"} {"type":"new_job_from_settings","name":null|"<name>"}
    {"type":"unsupported","reason":"exactDuration|pickup|guideTransfer|other","request":"<what they asked>"}

    Rules:
    - "Go for a take", "let's hear Birmingham read it", "again" → render. "Again" means variation "fresh".
    - Livelier / more fun / more energy / cheekier → variation "livelier". Calmer / less salesy / less pushy / warmer / more natural → "steadier".
    - "Stress ONLY" / "lean on only" / words in CAPITALS → emphasis. "A beat after today" → pause_after.
    - "Play it", "let's hear it", "go back to take two" → play / select_take. "That's the one" → approve.
    - Describing a kind of voice ("a woman in her thirties from Manchester", "someone more fun") is CASTING → casting_search, not render.
    - Exact durations, partial pickups ("just the last two words") and copying the director's own read ("like this") are not \
    possible yet → unsupported with the right reason.
    - Leave "say" empty when you choose actions (the studio reports results itself). Use "say" for questions, clarifications \
    and small talk. Keep it warm, brief and professional. British English.
    - If the request is ambiguous, ask one short question in "say" and choose no actions.
    """

    static let examples: [[String: String]] = [
        ["role": "user", "content": "STUDIO STATE:\ncurrent line: Line 01\ncurrent actor: Birmingham\n\nDirector: right, let's go for a take"],
        ["role": "assistant", "content": #"{"say":"","actions":[{"type":"render","line":"current","actor":null,"variation":"standard","emphasis":[],"pause_after":[]}]}"#],
        ["role": "user", "content": "STUDIO STATE:\ncurrent line: Line 01\ncurrent actor: Birmingham\n\nDirector: lovely. again, a bit more fun, and really lean on only"],
        ["role": "assistant", "content": #"{"say":"","actions":[{"type":"render","line":"current","actor":null,"variation":"livelier","emphasis":["only"],"pause_after":[]}]}"#],
        ["role": "user", "content": "STUDIO STATE:\ncurrent line: Line 02\ncurrent actor: Birmingham\n\nDirector: I want a woman in her early thirties from Manchester"],
        ["role": "assistant", "content": #"{"say":"","actions":[{"type":"casting_search","brief":"woman, early thirties, from Manchester"}]}"#],
        ["role": "user", "content": "STUDIO STATE:\ncurrent line: Line 01\ncurrent actor: Birmingham\n\nDirector: let's do line three, a bit slower"],
        ["role": "assistant", "content": #"{"say":"","actions":[{"type":"render","line":"3","actor":null,"variation":"steadier","emphasis":[],"pause_after":[]}]}"#],
        ["role": "user", "content": "STUDIO STATE:\ncurrent line: Line 01\ncurrent actor: Birmingham\n\nDirector: make it exactly twenty seconds"],
        ["role": "assistant", "content": #"{"say":"","actions":[{"type":"unsupported","reason":"exactDuration","request":"make it exactly twenty seconds"}]}"#],
        ["role": "user", "content": "STUDIO STATE:\ncurrent line: Line 01\ncurrent actor: Birmingham\n\nDirector: do it like this — TODAY only at our store"],
        ["role": "assistant", "content": #"{"say":"","actions":[{"type":"unsupported","reason":"guideTransfer","request":"do it like this — TODAY only at our store"}]}"#],
        ["role": "user", "content": "STUDIO STATE:\ncurrent line: Line 02\ncurrent actor: Birmingham\n\nDirector: how are we doing for time tonight?"],
        ["role": "assistant", "content": #"{"say":"No rush on my side. Want another pass at line two?","actions":[]}"#]
    ]

    public static func describe(_ c: EngineerContext) -> String {
        var s = "job: \(c.jobName ?? "none open")"
        if let l = c.languageTag { s += " (\(l))" }
        s += "\nscript lines: " + (c.lines.isEmpty ? "none" : c.lines.map { "\($0.number): \($0.text)" }.joined(separator: " | "))
        s += "\ncurrent line: \(c.currentLine)"
        s += "\ncurrent actor: \(c.currentActor ?? "none")"
        s += "\ncast in this job: " + (c.cast.isEmpty ? "nobody" : c.cast.joined(separator: ", "))
        if !c.castWithoutVoice.isEmpty { s += " (stand-ins with no voice: \(c.castWithoutVoice.joined(separator: ", ")))" }
        s += "\nvoices in library: " + (c.voicesInLibrary.isEmpty ? "none" : c.voicesInLibrary.joined(separator: ", "))
        let takes = c.takes.map { "\($0.line) \($0.actor) take \($0.number)\($0.approved ? " (approved)" : "")\($0.selected ? " [selected]" : "")" }
        s += "\ntakes: " + (takes.isEmpty ? "none" : takes.suffix(12).joined(separator: "; "))
        if c.rendering { s += "\na render is in progress" }
        if c.awaitingWelcomeChoice { s += "\nthe director has just reopened this job and is choosing: continue it, or a new job with the same settings" }
        if !c.recentJobs.isEmpty { s += "\nrecent jobs: \(c.recentJobs.prefix(8).joined(separator: ", "))" }
        return s
    }

    static func jsonString(_ s: String) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8), as: UTF8.self).dropFirst().dropLast().description
    }

    /// Accepts the first {...} object in the reply (models sometimes add fences or <think> blocks).
    public static func parse(_ raw: String, source: String) throws -> Interpretation {
        var text = raw
        if let r = text.range(of: "</think>") { text = String(text[r.upperBound...]) }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let obj = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any]
        else { throw OpenAICompatibleProvider.ProviderError.unparseable(raw) }
        let say = (obj["say"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let actions = ((obj["actions"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.compactMap(action)
        return Interpretation(actions: actions, reply: say?.isEmpty == false ? say : nil, source: source)
    }

    static func line(_ v: Any?) -> LineRef {
        if let n = v as? Int { return .number(n) }
        guard let s = (v as? String)?.lowercased() else { return .current }
        switch s {
        case "full", "fullread", "full read", "all": return .fullRead
        case "next": return .next
        case "previous": return .previous
        case "last": return .last
        default: return Int(s.filter(\.isNumber)).map(LineRef.number) ?? .current
        }
    }

    static func take(_ v: Any?) -> TakeRef {
        if let n = v as? Int { return .number(n) }
        guard let s = (v as? String)?.lowercased() else { return .current }
        switch s {
        case "latest", "last", "newest": return .latest
        case "previous": return .previous
        default: return Int(s.filter(\.isNumber)).map(TakeRef.number) ?? .current
        }
    }

    static func words(_ v: Any?) -> [String] {
        ((v as? [Any]) ?? []).compactMap { $0 as? String }.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) }.filter { !$0.isEmpty }
    }

    static func action(_ a: [String: Any]) -> EngineerAction? {
        let name = { (k: String) in (a[k] as? String)?.trimmingCharacters(in: .whitespaces) }
        switch (a["type"] as? String ?? "").lowercased() {
        case "render":
            let d = PerformanceDirection(variation: PerformanceDirection.Variation(rawValue: name("variation") ?? "standard") ?? .standard,
                                         emphasis: words(a["emphasis"]), pauseAfter: words(a["pause_after"]))
            return .render(line: line(a["line"]), actor: name("actor").flatMap { $0.isEmpty ? nil : $0 }, direction: d)
        case "play": return .play(take(a["take"]))
        case "stop": return .stop
        case "approve": return .approve(take(a["take"]))
        case "unapprove": return .unapprove(take(a["take"]))
        case "select_line": return .selectLine(line(a["line"]))
        case "select_take": return .selectTake(take(a["take"]))
        case "select_actor": return name("name").map(EngineerAction.selectActor)
        case "cast": return name("name").map(EngineerAction.cast)
        case "casting_search": return .castingSearch(name("brief") ?? "")
        case "export": return .export(take(a["take"]))
        case "open_job": return name("name").map(EngineerAction.openJob)
        case "list_jobs": return .listJobs
        case "list_voices": return .listVoices
        case "continue_job": return .continueJob
        case "new_job_from_settings": return .newJobFromSettings(name: name("name"))
        case "unsupported": return .unsupported(request: name("request") ?? "", reason: name("reason") ?? "other")
        default: return nil
        }
    }
}
