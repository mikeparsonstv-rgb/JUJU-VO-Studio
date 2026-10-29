import Foundation
import VOStudioCore

/// The Engineer operates exactly the same state and functions as the on-screen controls.
extension AppModel: StudioActions {
    var engineerContext: EngineerContext {
        var c = EngineerContext()
        guard let d = desk else {
            c.recentJobs = jobs.map(\.job.name); c.voicesInLibrary = voices.map(\.voice.displayName); return c
        }
        c.jobName = d.job.name
        c.languageTag = d.settings.languageTag
        c.lines = d.segments.map { .init(number: $0.stableLineNumber, text: $0.text) }
        c.currentLine = currentLineLabel
        let voiceIDs = Set(voices.map(\.voice.id))
        c.cast = d.bindings.filter { voiceIDs.contains($0.voiceMasterID) }.map(\.actorDisplayName)
        c.castWithoutVoice = d.bindings.filter { !voiceIDs.contains($0.voiceMasterID) }.map(\.actorDisplayName)
        c.currentActor = d.bindings.first { $0.id == selectedBindingID }?.actorDisplayName
        c.takes = d.takes.map { .init(line: $0.lineLabel, actor: $0.actorDisplayNameSnapshot, number: $0.perLineTakeNumber,
                                      approved: $0.isApproved, selected: $0.id == selectedTakeID) }
        c.voicesInLibrary = voices.map(\.voice.displayName)
        c.recentJobs = jobs.map(\.job.name)
        c.rendering = !activeRunsForDesk.isEmpty
        c.engine = engineStatus
        c.awaitingWelcomeChoice = welcome != nil
        return c
    }

    var currentLineLabel: String {
        guard let d = desk, let id = selectedSegmentID, let s = d.segments.first(where: { $0.id == id }) else { return "Full read" }
        return "Line \(String(format: "%02d", s.stableLineNumber))"
    }

    func playTake(_ id: UUID) { select(take: id); play() }

    func perform(_ action: EngineerAction) async -> ActionOutcome {
        guard let library else { return .init(ok: false, say: "The library isn't open.") }
        switch action {
        case .listJobs:
            refreshJobs()
            let names = jobs.prefix(4).map(\.job.name)
            return .init(ok: true, say: names.isEmpty ? "There are no jobs yet." : "Most recent: \(Speech.list(names)).")
        case .listVoices:
            return .init(ok: true, say: voices.isEmpty ? "There are no voices in the library yet." : "We've got \(Speech.list(voices.map(\.voice.displayName))).")
        case .openJob(let name):
            refreshJobs()
            let hits = jobs.filter { $0.job.name.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains($0.job.name) }
            if hits.count == 1 { open(hits[0].job.id); return .init(ok: true, say: "Opening \(hits[0].job.name).") }
            if hits.isEmpty { return .init(ok: false, say: "I can't find a job called \(name).") }
            return .init(ok: false, say: "Which one — \(Speech.list(hits.prefix(3).map(\.job.name), conjunction: "or"))?")
        case .castingSearch(let brief):
            _ = try? library.recordDirection(jobID: desk?.job.id ?? UUID(), segmentIDs: [], transcript: brief, source: "conversationDerived",
                                             intent: nil, proposedAction: "casting_search", confirmedAction: "casting_search")
            guard !voices.isEmpty else { return .init(ok: true, say: "There are no voices in the library yet. Add one under Voices and I can audition it.") }
            let list = voices.map { v in "\(v.voice.displayName) (\(Speech.language(v)))" }
            return .init(ok: true, say: "In the library right now: \(Speech.list(list)). That's everyone I've got, and I can't search for new voices yet.")
        case .cast(let name):
            guard desk != nil else { return .init(ok: false, say: "Open a job first.") }
            guard let v = voices.first(where: { $0.voice.displayName.caseInsensitiveCompare(name) == .orderedSame }) else {
                return .init(ok: false, say: "I haven't got a voice called \(name).")
            }
            castVoice(v.voice.id)
            return .init(ok: true, say: "\(v.voice.displayName)'s in.")
        case .selectActor(let name):
            guard let b = binding(named: name) ?? castIfAvailable(name) else { return .init(ok: false, say: "I haven't got anyone called \(name).") }
            selectedBindingID = b.id
            return .init(ok: true, say: "\(b.actorDisplayName) it is.")
        case .selectLine(let ref):
            guard let seg = resolveLine(ref) else { return .init(ok: false, say: lineMissing(ref)) }
            selectedSegmentID = seg
            select(take: takesOnCurrentLine().last?.id)
            return .init(ok: true, say: "\(spokenLine).")
        case .selectTake(let ref):
            guard let t = resolveTake(ref) else { return .init(ok: false, say: "I can't find that take on \(spokenLine).") }
            select(take: t.id)
            return .init(ok: true, say: nil)
        case .play(let ref):
            guard let t = resolveTake(ref) else { return .init(ok: false, say: "There's no take on \(spokenLine) yet.") }
            stop(); select(take: t.id)
            return .init(ok: true, say: "Take \(Speech.number(t.perLineTakeNumber)).", playAfterSpeaking: t.id)
        case .stop:
            stop()
            return .init(ok: true, say: "Stopped.")
        case .approve(let ref), .unapprove(let ref):
            let approve = { if case .approve = action { return true } else { return false } }()
            guard let t = resolveTake(ref) else { return .init(ok: false, say: "Which take? There isn't one selected.") }
            if t.isApproved == approve { return .init(ok: true, say: approve ? "That one's already approved." : "That one isn't approved.") }
            select(take: t.id); toggleApproval()
            return .init(ok: true, say: approve ? "Approved — \(t.actorDisplayNameSnapshot), \(spokenLine(for: t)), take \(Speech.number(t.perLineTakeNumber))."
                                               : "Approval taken off take \(Speech.number(t.perLineTakeNumber)).")
        case .export(let ref):
            guard let t = resolveTake(ref), let d = desk else { return .init(ok: false, say: "There's no take to export yet.") }
            let folder = library.root.appendingPathComponent("Exports").appendingPathComponent(CanonicalNaming.token(d.job.name, fallback: "Job"))
            do {
                let e = try library.exportTake(t.id, to: folder); reloadDesk()
                return .init(ok: true, say: "Exported take \(Speech.number(t.perLineTakeNumber)) to the Exports folder.", detail: e.lastKnownPath)
            } catch { return .init(ok: false, say: "I couldn't export that: \((error as? LocalizedError)?.errorDescription ?? "unknown error").") }
        case .continueJob:
            welcome = nil
            return .init(ok: true, say: "Great — carrying on with \(desk?.job.name ?? "this job").")
        case .newJobFromSettings(let name):
            guard let name, !name.isEmpty else { return .init(ok: true, say: "What shall we call the new job?", needs: "newJobName") }
            let before = desk?.job.id
            newJobFromSettings(name: name, copyScript: true)
            guard desk?.job.id != before else { return .init(ok: false, say: "I couldn't set that up.") }
            return .init(ok: true, say: "Done — \(name) has the same settings and cast, and the script. The old job is untouched.")
        case .unsupported(let request, let reason):
            if let d = desk {
                _ = try? library.recordDirection(jobID: d.job.id, segmentIDs: selectedSegmentID.map { [$0] } ?? [], transcript: request,
                                                 source: "conversationDerived", intent: nil, proposedAction: reason, confirmedAction: "unsupported")
            }
            switch reason {
            case "exactDuration": return .init(ok: true, say: "I can't hit an exact length with this voice yet. I can go again a bit tighter if you like.")
            case "pickup": return .init(ok: true, say: "I can't drop in just part of a line yet, so I'd redo the whole line. Shall I?")
            case "guideTransfer": return .init(ok: true, say: "I can't copy your read with this engine yet. Tell me which word to lean on and I'll try that.")
            default: return .init(ok: true, say: "That's beyond me at the moment — I've made a note of it.")
            }
        case .render(let lineRef, let actorName, let direction):
            guard desk != nil else { return .init(ok: false, say: "Open a job first.") }
            if let lineRef = Optional(lineRef), lineRef != .current {
                guard let seg = resolveLine(lineRef) else { return .init(ok: false, say: lineMissing(lineRef)) }
                selectedSegmentID = seg
            }
            if let actorName {
                guard let b = binding(named: actorName) ?? castIfAvailable(actorName) else { return .init(ok: false, say: "I haven't got anyone called \(actorName).") }
                selectedBindingID = b.id
            }
            guard let b = desk?.bindings.first(where: { $0.id == selectedBindingID }) ?? desk?.bindings.first else {
                return .init(ok: false, say: voices.isEmpty ? "Nobody's cast yet, and there are no voices in the library." : "Nobody's cast yet. Shall I cast \(voices[0].voice.displayName)?")
            }
            selectedBindingID = b.id
            guard voices.contains(where: { $0.voice.id == b.voiceMasterID }) else {
                return .init(ok: false, say: "\(b.actorDisplayName) is a stand-in with no voice. Cast a voice first.")
            }
            let busy = !activeRunsForDesk.isEmpty
            var d = direction
            if d.note.isEmpty { d.note = direction.variation.rawValue }
            guard let run = await render(d, source: "conversationDerived") else { return .init(ok: false, say: "I couldn't start that render.") }
            var say: String
            switch direction.variation {
            case .standard: say = "Okay, locking in \(b.actorDisplayName) for this next read."
            case .fresh: say = "Going again."
            case .livelier: say = "Sure — more life in it this time."
            case .steadier: say = "Okay, calmer this time."
            }
            if !direction.emphasis.isEmpty { say += " Leaning on “\(direction.emphasis.joined(separator: "”, “"))” — that's experimental with this voice." }
            if !direction.pauseAfter.isEmpty { say += " With a beat after “\(direction.pauseAfter[0])”." }
            if lineRef != .current { say = "\(spokenLine.capitalizedFirst). " + say }
            if busy { say += " It's queued behind the one that's rendering." }
            return .init(ok: true, say: say, queuedRunID: run.id)
        }
    }

    // MARK: Resolution helpers

    private func binding(named name: String) -> JobActorBinding? {
        desk?.bindings.first { $0.actorDisplayName.caseInsensitiveCompare(name) == .orderedSame || $0.fileToken.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func castIfAvailable(_ name: String) -> JobActorBinding? {
        guard let v = voices.first(where: { $0.voice.displayName.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        castVoice(v.voice.id)
        return desk?.bindings.first { $0.voiceMasterID == v.voice.id }
    }

    private func resolveLine(_ ref: LineRef) -> UUID?? {
        guard let segs = desk?.segments else { return nil }
        let idx = segs.firstIndex { $0.id == selectedSegmentID }
        switch ref {
        case .current: return .some(selectedSegmentID)
        case .fullRead: return .some(nil)
        case .number(let n): return segs.first { $0.stableLineNumber == n }.map { .some($0.id) }
        case .next: guard let i = idx, i + 1 < segs.count else { return segs.first.map { .some($0.id) } }; return .some(segs[i + 1].id)
        case .previous: guard let i = idx, i > 0 else { return nil }; return .some(segs[i - 1].id)
        case .last: return segs.last.map { .some($0.id) }
        }
    }

    private func lineMissing(_ ref: LineRef) -> String {
        if case .number(let n) = ref { return "There's no line \(Speech.number(n)) — the script has \(desk?.segments.count ?? 0) lines." }
        return "There isn't a line there."
    }

    private func takesOnCurrentLine() -> [Take] {
        guard let d = desk else { return [] }
        let onLine = d.takes.filter { $0.segmentID == selectedSegmentID }
        let mine = onLine.filter { $0.actorBindingID == selectedBindingID }
        return (mine.isEmpty ? onLine : mine).sorted { $0.perLineTakeNumber < $1.perLineTakeNumber }
    }

    private func resolveTake(_ ref: TakeRef) -> Take? {
        let list = takesOnCurrentLine()
        switch ref {
        case .current: return list.first { $0.id == selectedTakeID } ?? list.last
        case .latest: return list.last
        case .number(let n): return list.first { $0.perLineTakeNumber == n }
        case .previous:
            guard let cur = list.firstIndex(where: { $0.id == selectedTakeID }) ?? (list.isEmpty ? nil : list.count - 1), cur > 0 else { return nil }
            return list[cur - 1]
        }
    }

    var spokenLine: String {
        guard let d = desk, let id = selectedSegmentID, let s = d.segments.first(where: { $0.id == id }) else { return "the full read" }
        return "line \(Speech.number(s.stableLineNumber))"
    }
    private func spokenLine(for t: Take) -> String { t.lineKey == 0 ? "the full read" : "line \(Speech.number(t.lineKey))" }
}

enum Speech {
    static func number(_ n: Int) -> String { AppModel.spoken(n) }
    static func list(_ items: [String], conjunction: String = "and") -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " \(conjunction) " + items.last!
    }
    static func language(_ v: VoiceSummary) -> String {
        Languages.all.first { $0.tag == v.voice.languageTag }?.name ?? (v.voice.languageTag ?? "")
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
