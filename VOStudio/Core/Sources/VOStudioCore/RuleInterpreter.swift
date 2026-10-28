import Foundation

/// Instant, deterministic understanding of common studio talk. Returns nil when it isn't confident,
/// so the utterance goes to the conversational model instead. Never guesses actor names it can't see.
public struct RuleInterpreter: Sendable {
    public init() {}

    static let numberWords: [String: Int] = [
        "one": 1, "first": 1, "1st": 1, "two": 2, "second": 2, "2nd": 2, "three": 3, "third": 3, "3rd": 3,
        "four": 4, "fourth": 4, "4th": 4, "five": 5, "fifth": 5, "5th": 5, "six": 6, "sixth": 6, "seven": 7, "seventh": 7,
        "eight": 8, "eighth": 8, "nine": 9, "ninth": 9, "ten": 10, "tenth": 10, "eleven": 11, "twelve": 12
    ]

    static func number(_ token: String) -> Int? { Int(token) ?? numberWords[token] }

    public func interpret(_ raw: String, context: EngineerContext) -> Interpretation? {
        let u = Self.normalise(raw)
        guard !u.isEmpty else { return nil }
        func has(_ phrases: [String]) -> Bool { phrases.contains { u.range(of: "\\b" + $0 + "\\b", options: .regularExpression) != nil } }

        // Welcome choice after a WAV drop / reopened job.
        if context.awaitingWelcomeChoice {
            if has(["make (some )?changes", "carry on", "continue", "same job", "this job", "changes to this"]) { return .init(actions: [.continueJob], source: "rules") }
            if has(["something new", "new job", "fresh job", "same settings"]) { return .init(actions: [.newJobFromSettings(name: Self.quotedName(u))], source: "rules") }
        }

        // Honest refusals for things the local engine can't do yet.
        if has(["make it \\d+ seconds", "\\d+ seconds long", "exactly \\d+ seconds", "fit (it )?(in|to) \\d+"]) {
            return .init(actions: [.unsupported(request: raw, reason: "exactDuration")], source: "rules")
        }
        if has(["just the last (two |three |\\w+ )?words?", "only the last (two |\\w+ )?words?", "just the (first|last) (bit|part|word)", "keep (that|the) first (sentence|bit|half)"]) {
            return .init(actions: [.unsupported(request: raw, reason: "pickup")], source: "rules")
        }
        if has(["like this", "like i('m| am) doing", "copy (my|this) read", "do it the way i"]) && !has(["stress", "emphasi[sz]e", "lean on", "punch"]) {
            return .init(actions: [.unsupported(request: raw, reason: "guideTransfer")], source: "rules")
        }

        if has(["stop", "hold on", "hang on", "wait", "shh+", "quiet"]) && u.split(separator: " ").count <= 4 {
            return .init(actions: [.stop], source: "rules")
        }

        let line = Self.lineRef(u)
        let take = Self.takeRef(u)

        // Approval.
        if has(["that's the one", "thats the one", "that is the one", "approve( it| that| this)?", "keeper", "print (it|that)", "we'll have that", "nailed it"]) {
            return .init(actions: [.approve(take ?? .current)], source: "rules")
        }
        if has(["unapprove", "not approved", "scrap that approval", "take (that|the) approval off"]) {
            return .init(actions: [.unapprove(take ?? .current)], source: "rules")
        }
        if has(["export( it| that| this)?", "bounce (it|that|this)", "send (me )?(it|that)"]) {
            return .init(actions: [.export(take ?? .current)], source: "rules")
        }

        // Going back / playing.
        if has(["go back to", "back to (the )?(take|previous|last|\\w+ take)", "previous take", "play (me )?take", "play (the )?\\w+ take"]) , let t = take ?? (has(["previous"]) ? .previous : nil) {
            return .init(actions: [.selectTake(t), .play(t)], source: "rules")
        }
        if has(["play( it| that| this| back| me that| again)?", "let's hear (it|that)( again)?", "lets hear (it|that)( again)?", "listen back", "hear it back", "one more listen"]) {
            return .init(actions: [.play(take ?? .current)], source: "rules")
        }

        // Rendering.
        let direction = Self.direction(u, raw: raw)
        let renderVerb = has(["go for (a |another |one more )?take", "(let's|lets|let us) (go|do|try)( it)?( again)?", "(do|give me|try) (a |another |one more )?(take|read|go)",
                              "again", "go again", "one more( time)?", "another (one|take|read)", "from the top", "render( it| that| line \\w+| the \\w+)?",
                              "record( it)?", "read (it|line \\w+|the \\w+ line)", "take it", "have a go", "run it"])
        if renderVerb || (!direction.isEmpty && has(["more", "less", "bit", "little", "stress", "emphasi[sz]e", "lean on", "punch", "pause"])) {
            var dir = direction
            if dir.variation == .standard, has(["again", "go again", "one more", "another", "fresh"]) { dir.variation = .fresh }
            dir.note = raw
            let actor = Self.actorMention(u, context: context)
            return .init(actions: [.render(line: line ?? .current, actor: actor, direction: dir)], source: "rules")
        }

        // Navigation.
        if let l = line, has(["go to", "move to", "next line", "previous line", "last line", "line \\w+", "full read", "whole (thing|script)"]) && u.split(separator: " ").count <= 6 {
            return .init(actions: [.selectLine(l)], source: "rules")
        }
        if has(["try", "switch to", "use", "go with"]), let actor = Self.actorMention(u, context: context) {
            return .init(actions: [.selectActor(actor), .render(line: line ?? .current, actor: actor, direction: .init(note: raw))], source: "rules")
        }
        if has(["who (have we|do we have|is available|have you)( got)?", "what voices", "which voices", "voice list", "who's available"]) {
            return .init(actions: [.listVoices], source: "rules")
        }
        if has(["recent jobs", "what jobs", "list (the )?jobs", "previous jobs"]) { return .init(actions: [.listJobs], source: "rules") }
        return nil
    }

    // MARK: Pieces

    static func normalise(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "[^a-z0-9' ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func lineRef(_ u: String) -> LineRef? {
        if u.range(of: "\\b(full read|whole (thing|script|lot)|all of it|from the top|the lot)\\b", options: .regularExpression) != nil { return .fullRead }
        if u.contains("next line") { return .next }
        if u.contains("previous line") || u.contains("line before") { return .previous }
        if u.contains("last line") || u.contains("final line") { return .last }
        if let m = u.range(of: "\\bline (\\w+)\\b", options: .regularExpression) {
            let tok = String(u[m]).split(separator: " ").last.map(String.init) ?? ""
            if let n = number(tok) { return .number(n) }
        }
        if let m = u.range(of: "\\b(\\w+) line\\b", options: .regularExpression) {
            let tok = String(u[m]).split(separator: " ").first.map(String.init) ?? ""
            if let n = number(tok) { return .number(n) }
        }
        return nil
    }

    static func takeRef(_ u: String) -> TakeRef? {
        if let m = u.range(of: "\\btake (\\w+)\\b", options: .regularExpression) {
            let tok = String(u[m]).split(separator: " ").last.map(String.init) ?? ""
            if let n = number(tok) { return .number(n) }
            if tok == "before" { return .previous }
        }
        if let m = u.range(of: "\\b(\\w+) (take|one|read)\\b", options: .regularExpression) {
            let tok = String(u[m]).split(separator: " ").first.map(String.init) ?? ""
            if tok == "previous" || tok == "last" && u.contains("back") { return .previous }
            if tok != "one", let n = number(tok), n <= 20 { return .number(n) }
        }
        if u.contains("previous") || u.contains("one before") { return .previous }
        if u.contains("latest") || u.contains("newest") { return .latest }
        return nil
    }

    static func direction(_ u: String, raw: String) -> PerformanceDirection {
        var d = PerformanceDirection()
        let lively = ["livelier", "more lively", "more energy", "more energetic", "more fun", "more upbeat", "brighter", "punchier", "more excited",
                      "more mischievous", "more playful", "cheekier", "more cheeky", "bigger", "more salesy", "more animated", "more character", "more attitude"]
        let steady = ["steadier", "calmer", "less salesy", "softer", "more relaxed", "less pushy", "more natural", "tone it down", "less over the top",
                      "more laid back", "less shouty", "gentler", "warmer", "more conversational", "less cheesy", "less cheerful", "more sincere", "slower"]
        if lively.contains(where: u.contains) { d.variation = .livelier }
        else if steady.contains(where: u.contains) { d.variation = .steadier }
        let stressPattern = "\\b(?:stress|emphasi[sz]e|emphasis on|lean on|punch|hit|more on|land) (?:the word |on )?([a-z']+)"
        if let re = try? NSRegularExpression(pattern: stressPattern), let m = re.firstMatch(in: u, range: NSRange(u.startIndex..., in: u)),
           let r = Range(m.range(at: 1), in: u) {
            let w = String(u[r]); if !["it", "that", "this", "the", "a"].contains(w) { d.emphasis = [w] }
        }
        // Words the director shouted in CAPS in typed direction ("today ONLY at our store").
        let caps = raw.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init).filter { $0.count > 1 && $0 == $0.uppercased() && $0.lowercased() != $0 }
        for c in caps where !d.emphasis.contains(c.lowercased()) && c != "OK" { d.emphasis.append(c.lowercased()) }
        let pausePattern = "\\b(?:pause|beat|breath|breathe) after ([a-z']+)"
        if let re = try? NSRegularExpression(pattern: pausePattern), let m = re.firstMatch(in: u, range: NSRange(u.startIndex..., in: u)),
           let r = Range(m.range(at: 1), in: u) { d.pauseAfter = [String(u[r])] }
        return d
    }

    /// Only names already cast in this job count — never invented.
    static func actorMention(_ u: String, context: EngineerContext) -> String? {
        let names = (context.cast + context.voicesInLibrary).sorted { $0.count > $1.count }
        return names.first { u.range(of: "\\b" + NSRegularExpression.escapedPattern(for: normalise($0)) + "\\b", options: .regularExpression) != nil }
    }

    static func quotedName(_ u: String) -> String? {
        guard let r = u.range(of: "(called|named) (.+)$", options: .regularExpression) else { return nil }
        return String(u[r]).replacingOccurrences(of: "^(called|named) ", with: "", options: .regularExpression)
    }
}
