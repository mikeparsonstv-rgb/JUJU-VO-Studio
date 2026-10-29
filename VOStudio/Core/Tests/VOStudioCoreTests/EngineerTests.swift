import Foundation
import Testing
@testable import VOStudioCore

@MainActor
private final class FakeStudio: StudioActions {
    var performed: [EngineerAction] = []
    var played: [UUID] = []
    var outcomes: [String: ActionOutcome] = [:]
    var engineerContext: EngineerContext = {
        var c = EngineerContext()
        c.jobName = "Daz Autumn"; c.currentLine = "Line 01"; c.currentActor = "Birmingham"; c.cast = ["Birmingham"]
        c.voicesInLibrary = ["Birmingham"]; c.lines = [.init(number: 1, text: "Today only at our store.")]
        return c
    }()
    func perform(_ action: EngineerAction) async -> ActionOutcome {
        performed.append(action)
        return outcomes[action.name] ?? ActionOutcome(ok: true, say: "ok \(action.name)")
    }
    func playTake(_ id: UUID) { played.append(id) }
}

@MainActor
private final class FakeVoice: EngineerVoice {
    var spoken: [String] = []
    func speak(_ text: String) async { spoken.append(text) }
    func stopSpeaking() {}
}

private struct StubProvider: ConversationProvider {
    var name = "stub"
    var result: Result<Interpretation, Error>
    func interpret(_ u: String, context: EngineerContext, history: [EngineerTurn]) async throws -> Interpretation { try result.get() }
}

private let ctx: EngineerContext = {
    var c = EngineerContext(); c.cast = ["Birmingham", "Jane"]; c.voicesInLibrary = ["Birmingham"]; c.currentActor = "Birmingham"; return c
}()

private func rule(_ s: String, _ c: EngineerContext = ctx) -> [EngineerAction]? { RuleInterpreter().interpret(s, context: c)?.actions }

@Test func commonStudioPhrasesAreUnderstoodInstantly() {
    if case .render(.current, nil, let d)? = rule("Right, let's go for a take")?.first { #expect(d.variation == .standard) } else { Issue.record("go for a take") }
    if case .render(_, _, let d)? = rule("Again, a bit more fun")?.first { #expect(d.variation == .livelier) } else { Issue.record("again more fun") }
    if case .render(_, _, let d)? = rule("Again, less salesy")?.first { #expect(d.variation == .steadier) } else { Issue.record("less salesy") }
    if case .render(_, _, let d)? = rule("one more time")?.first { #expect(d.variation == .fresh) } else { Issue.record("one more time") }
    if case .render(.number(3), _, _)? = rule("let's do line three")?.first {} else { Issue.record("line three") }
    if case .render(.fullRead, _, _)? = rule("take it from the top")?.first {} else { Issue.record("from the top") }
    if case .render(_, _, let d)? = rule("Go again and really lean on only")?.first { #expect(d.emphasis == ["only"]) } else { Issue.record("lean on only") }
    if case .render(_, _, let d)? = rule("again — today ONLY at our store")?.first { #expect(d.emphasis == ["only"]) } else { Issue.record("CAPS emphasis") }
    if case .render(_, _, let d)? = rule("again with a beat after today")?.first { #expect(d.pauseAfter == ["today"]) } else { Issue.record("beat after") }
    #expect(rule("That's the one!") == [.approve(.current)])
    #expect(rule("play it back") == [.play(.current)])
    #expect(rule("Go back to the second take") == [.selectTake(.number(2)), .play(.number(2))])
    #expect(rule("go back to take 3") == [.selectTake(.number(3)), .play(.number(3))])
    #expect(rule("stop") == [.stop])
    #expect(rule("next line") == [.selectLine(.next)])
    if case .selectActor("Jane")? = rule("Try Jane instead")?.first {} else { Issue.record("try Jane") }
    #expect(rule("who have we got?") == [.listVoices])
}

@Test func impossibleRequestsAreRefusedHonestlyNotFaked() {
    if case .unsupported(_, "exactDuration")? = rule("make it 30 seconds")?.first {} else { Issue.record("duration") }
    if case .unsupported(_, "pickup")? = rule("just the last two words, more conviction")?.first {} else { Issue.record("pickup") }
    if case .unsupported(_, "guideTransfer")? = rule("can you make it more like this, today only at our store")?.first {} else { Issue.record("guide") }
}

@Test func castingTalkAndUnknownNamesGoToTheModel() {
    #expect(rule("I want a woman in her early thirties from Manchester") == nil)
    #expect(rule("She's a bit posh, have we got someone more fun?") == [.castingSearch("She's a bit posh, have we got someone more fun?")])
    if case .render(_, _, let d)? = rule("Same girl, a bit less cheerful, go again")?.first { #expect(d.variation == .steadier) } else { Issue.record("same girl") }
    #expect(rule("try Lucy") == nil)                                  // never invents an actor that isn't cast
}

@Test func welcomeChoiceIsUnderstood() {
    var c = ctx; c.awaitingWelcomeChoice = true
    #expect(rule("let's make some changes", c) == [.continueJob])
    #expect(rule("something new with the same settings", c) == [.newJobFromSettings(name: nil)])
}

@Test func modelRepliesAreParsedTolerantly() throws {
    let raw = "<think>hmm</think>```json\n{\"say\":\"\",\"actions\":[{\"type\":\"render\",\"line\":\"2\",\"actor\":null,\"variation\":\"livelier\",\"emphasis\":[\"Only\"],\"pause_after\":[]},{\"type\":\"bogus\"}]}\n```"
    let i = try EngineerPrompt.parse(raw, source: "t")
    #expect(i.actions == [.render(line: .number(2), actor: nil, direction: .init(variation: .livelier, emphasis: ["only"]))])
    #expect(i.reply == nil)
    let q = try EngineerPrompt.parse(#"{"say":"Which take, two or three?","actions":[]}"#, source: "t")
    #expect(q.actions.isEmpty && q.reply == "Which take, two or three?")
    #expect(throws: (any Error).self) { try EngineerPrompt.parse("I think you should", source: "t") }
    let c = try EngineerPrompt.parse(#"{"actions":[{"type":"casting_search","brief":"woman, 30s, Manchester"},{"type":"unsupported","reason":"pickup","request":"x"}]}"#, source: "t")
    #expect(c.actions == [.castingSearch("woman, 30s, Manchester"), .unsupported(request: "x", reason: "pickup")])
}

@MainActor @Test func engineerUsesRulesFirstAndSpeaksWhatActuallyHappened() async {
    let studio = FakeStudio(), voice = FakeVoice()
    studio.outcomes["render"] = ActionOutcome(ok: true, say: "Okay, locking in Birmingham for this next read.", queuedRunID: UUID())
    let e = Engineer(studio: studio, voice: voice, provider: StubProvider(result: .failure(CancellationError())))
    await e.connect(greeting: "Hi, I'm here.")
    await e.hear("Let's go for a take")
    #expect(studio.performed.count == 1 && studio.performed[0].name == "render")
    #expect(voice.spoken == ["Hi, I'm here.", "Okay, locking in Birmingham for this next read."])
    #expect(e.latencies.first?.source == "rules")
    #expect(e.state == .listening)
}

@MainActor @Test func modelHandlesWhatRulesCannotAndFailuresAreHonest() async {
    let studio = FakeStudio(), voice = FakeVoice()
    studio.outcomes["casting_search"] = ActionOutcome(ok: true, say: "From the library I can offer Birmingham. I can't confirm a Manchester accent.")
    let e = Engineer(studio: studio, voice: voice,
                     provider: StubProvider(result: .success(.init(actions: [.castingSearch("woman, 30s, Manchester")], reply: "Sure!", source: "stub"))))
    await e.connect()
    await e.hear("I'd like an English female voice, early thirties, from Manchester")
    #expect(studio.performed == [.castingSearch("woman, 30s, Manchester")])
    #expect(voice.spoken.last == "From the library I can offer Birmingham. I can't confirm a Manchester accent.")   // studio truth, not the model's "Sure!"
    e.provider = StubProvider(result: .failure(URLError(.timedOut)))
    await e.hear("tell me a joke about compressors")
    #expect(voice.spoken.last == "Sorry, I lost that one. Say it again?")
    #expect(e.log.contains { $0.speaker == .system && $0.text.contains("Language model error") })
}

@MainActor @Test func readyIsAnnouncedOnlyWhenTheTakeExistsThenPlayed() async {
    let studio = FakeStudio(), voice = FakeVoice()
    let run = UUID(), take = UUID()
    studio.outcomes["render"] = ActionOutcome(ok: true, say: "Okay.", queuedRunID: run)
    let e = Engineer(studio: studio, voice: voice)
    await e.connect()
    await e.hear("go for a take")
    #expect(!voice.spoken.contains("That's ready, here you go."))
    #expect(await e.renderFinished(runID: UUID(), takeID: take, error: nil) == false)      // someone else's render
    #expect(await e.renderFinished(runID: run, takeID: take, error: nil))
    #expect(voice.spoken.last == "That's ready, here you go." && studio.played == [take])
}

@MainActor @Test func failedRenderIsReportedNotPlayed() async {
    let studio = FakeStudio(), voice = FakeVoice()
    let run = UUID()
    studio.outcomes["render"] = ActionOutcome(ok: true, say: "Okay.", queuedRunID: run)
    let e = Engineer(studio: studio, voice: voice)
    await e.connect(); await e.hear("again")
    await e.renderFinished(runID: run, takeID: nil, error: "Qwen worker exited unexpectedly. stderr…")
    #expect(voice.spoken.last == "That one didn't come through — Qwen worker exited unexpectedly." && studio.played.isEmpty)
}

@MainActor @Test func followUpQuestionCompletesTheAction() async {
    let studio = FakeStudio(), voice = FakeVoice()
    var c = studio.engineerContext; c.awaitingWelcomeChoice = true; studio.engineerContext = c
    studio.outcomes["new_job_from_settings"] = ActionOutcome(ok: true, say: "What shall we call the new job?", needs: "newJobName")
    let e = Engineer(studio: studio, voice: voice)
    await e.connect()
    await e.hear("something new with the same settings")
    studio.outcomes["new_job_from_settings"] = ActionOutcome(ok: true, say: "Done — Daz Spring is ready.")
    await e.hear("Daz Spring")
    #expect(studio.performed == [.newJobFromSettings(name: nil), .newJobFromSettings(name: "Daz Spring")])
}

@MainActor @Test func playbackWaitsUntilTheEngineerHasSpoken() async {
    let studio = FakeStudio(), voice = FakeVoice()
    let t = UUID()
    studio.outcomes["play"] = ActionOutcome(ok: true, say: "Take two.", playAfterSpeaking: t)
    let e = Engineer(studio: studio, voice: voice)
    await e.connect(); await e.hear("play it back")
    #expect(voice.spoken == ["Take two."] && studio.played == [t])
    #expect(e.latencySummary.contains("1 turns"))
}

@MainActor @Test func nothingIsHeardWhileDisconnected() async {
    let studio = FakeStudio()
    let e = Engineer(studio: studio, voice: FakeVoice())
    await e.hear("go for a take")
    #expect(studio.performed.isEmpty)
}
