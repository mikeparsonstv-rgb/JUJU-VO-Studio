import Foundation
import Testing
import GRDB
import BroadcastWave
@testable import VOStudioCore

private func lib() throws -> StudioLibrary {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("vos2-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return try StudioLibrary(root: d, appBuild: "test", timeZone: TimeZone(identifier: "Europe/London")!)
}

private func reference(_ lib: StudioLibrary) throws -> URL {
    let u = lib.root.appendingPathComponent("ref.wav")
    try MockTone.wav(seconds: 1.0, frequency: 180).write(to: u)
    return u
}

private func setUp() async throws -> (StudioLibrary, RenderCoordinator, Job, JobActorBinding, VoiceSummary) {
    let l = try lib()
    let voice = try l.addVoice(displayName: "Birmingham", origin: "hostCloned", languageTag: "en-GB",
                               rightsNotes: "test", referenceWAV: try reference(l), transcript: "Are you ready?")
    let job = try l.createJob(name: "Daz Spring", script: "Today only at our store.\nDaz gel. It's a dose of common sense.")
    let binding = try l.cast(voiceMasterID: voice.voice.id, into: job.id)
    let rc = RenderCoordinator(library: l)
    await rc.register(MockActorEngine())
    return (l, rc, job, binding, voice)
}

@Test func voiceIsStoredWithHashedLocalReferenceAndCastUnderItsOwnName() async throws {
    let (l, _, job, binding, voice) = try await setUp()
    #expect(voice.references.count == 1 && voice.references[0].sha256.count == 64 && voice.references[0].transcript == "Are you ready?")
    #expect(binding.actorDisplayName == "Birmingham" && binding.fileToken == "Birmingham")
    #expect(try l.cast(voiceMasterID: voice.voice.id, into: job.id).id == binding.id)          // casting twice is idempotent
    #expect(try l.voices().map(\.voice.displayName) == ["Birmingham"])
    #expect(throws: (any Error).self) {                                                         // references are immutable
        try l.db.write { try $0.execute(sql: "UPDATE voiceReference SET sha256='x'") }
    }
}

@Test func renderRunIsPersistedFirstThenBecomesAValidatedTakeWithFullProvenance() async throws {
    let (l, rc, job, binding, _) = try await setUp()
    let seg = try l.desk(job.id).segments[0]
    let run = try await rc.enqueue(jobID: job.id, actorBindingID: binding.id, segmentID: seg.id, engineID: "mock")
    #expect(run.state == "queued")
    #expect(try l.renderRuns(jobID: job.id).first?.id == run.id)                                 // persisted before the engine runs
    await rc.drain()
    let done = try l.renderRuns(jobID: job.id).first!
    #expect(done.state == "succeeded" && done.takeID != nil && done.finishedAt != nil)
    let take = try l.desk(job.id).takes.first { $0.id == done.takeID }!
    #expect(take.canonicalBasename == "DazSpring-Birmingham-\(take.productionDate)-Line01-Take01")
    #expect(take.provenance == "mockFixture")                                                    // mock engine output stays labelled
    let snap = try l.snapshot(for: take)!
    #expect(snap.engineBuild?.hasPrefix("mock") == true && snap.randomSeed != nil && snap.rendererProfileID != nil)
    #expect(snap.conditioningJSON?.contains("referenceSHA256") == true)
    #expect(snap.resolvedSettingsJSON.contains("\"textSent\":\"Today only at our store.\""))
    let renders = l.root.appendingPathComponent("Library/\(job.id.uuidString.lowercased())/renders")
    #expect(((try? FileManager.default.contentsOfDirectory(atPath: renders.path)) ?? []).isEmpty)   // temp output consumed
}

@Test func rendersAreSerialAndNumberedAndAProfileIsReused() async throws {
    let (l, rc, job, binding, _) = try await setUp()
    let seg = try l.desk(job.id).segments[1]
    for _ in 0..<3 { try await rc.enqueue(jobID: job.id, actorBindingID: binding.id, segmentID: seg.id, engineID: "mock") }
    await rc.drain()
    let takes = try l.desk(job.id).takes
    #expect(takes.map(\.perLineTakeNumber) == [1, 2, 3])
    let profiles = Set(try takes.map { try l.snapshot(for: $0)!.rendererProfileID })
    #expect(profiles.count == 1)
}

@Test func fullReadRendersTheWholeScript() async throws {
    let (l, rc, job, binding, _) = try await setUp()
    try await rc.enqueue(jobID: job.id, actorBindingID: binding.id, segmentID: nil, engineID: "mock")
    await rc.drain()
    let take = try l.desk(job.id).takes[0]
    #expect(take.lineKey == 0 && take.canonicalBasename.contains("-FullRead-Take01"))
    #expect(try l.snapshot(for: take)!.resolvedSettingsJSON.contains("Today only at our store.\\nDaz gel."))
}

@Test func engineFailureIsRecordedHonestlyAndLeavesNoTake() async throws {
    let (l, _, job, binding, _) = try await setUp()
    let rc = RenderCoordinator(library: l)
    await rc.register(MockActorEngine(failNext: true))
    try await rc.enqueue(jobID: job.id, actorBindingID: binding.id, segmentID: nil, engineID: "mock")
    await rc.drain()
    let run = try l.renderRuns(jobID: job.id)[0]
    #expect(run.state == "failed" && run.error?.contains("mock engine failure") == true && run.takeID == nil)
    #expect(try l.desk(job.id).takes.isEmpty)
    #expect(throws: (any Error).self) { try l.db.write { try $0.execute(sql: "UPDATE renderRun SET state='succeeded'") } }  // final
}

@Test func placeholdersAndUnknownEnginesCannotRender() async throws {
    let (l, rc, job, _, _) = try await setUp()
    let ph = try l.addPlaceholderActor(jobID: job.id, displayName: "Stand-in")
    await #expect(throws: (any Error).self) { try await rc.enqueue(jobID: job.id, actorBindingID: ph.id, segmentID: nil, engineID: "mock") }
    let b = try l.desk(job.id).bindings.first { $0.actorDisplayName == "Birmingham" }!
    await #expect(throws: (any Error).self) { try await rc.enqueue(jobID: job.id, actorBindingID: b.id, segmentID: nil, engineID: "nope") }
}

@Test func missingReferenceFailsTheRunNotTheApp() async throws {
    let (l, rc, job, binding, voice) = try await setUp()
    try FileManager.default.removeItem(atPath: voice.references[0].localPath)
    try await rc.enqueue(jobID: job.id, actorBindingID: binding.id, segmentID: nil, engineID: "mock")
    await rc.drain()
    let run = try l.renderRuns(jobID: job.id)[0]
    #expect(run.state == "failed" && run.error?.contains("reference recording is missing") == true)
}

@Test func directionIsRecordedAndTranslatedIntoTextMarkupWithDisclosure() async throws {
    let (l, rc, job, binding, _) = try await setUp()
    let seg = try l.desk(job.id).segments[0]
    let dir = PerformanceDirection(variation: .livelier, emphasis: ["only"], pauseAfter: ["today"], note: "more like this — today ONLY")
    let e = try l.recordDirection(jobID: job.id, segmentIDs: [seg.id], transcript: dir.note, source: "manualText", intent: dir,
                                  proposedAction: "render", confirmedAction: "render")
    try await rc.enqueue(jobID: job.id, actorBindingID: binding.id, segmentID: seg.id, engineID: "mock", direction: dir, directionEventID: e.id)
    await rc.drain()
    let take = try l.desk(job.id).takes[0]
    let json = try l.snapshot(for: take)!.resolvedSettingsJSON
    #expect(json.contains("Today... ONLY at our store."))
    #expect(json.contains(e.id.uuidString.uppercased()) || json.contains(e.id.uuidString.lowercased()))
    #expect(take.segmentTextSnapshot == "Today only at our store.")                               // the copy itself is untouched
    #expect(try l.directions(jobID: job.id).first?.source == "manualText")
}

@Test func textMarkupIsWholeWordAndReportsWhatItDid() {
    let (t, applied) = TextMarkup.apply("Only the onlyest. Today, only today.", emphasis: ["only"], pauseAfter: ["today"])
    #expect(t == "ONLY the onlyest. Today... ONLY today.")
    #expect(applied.count == 2)
    let (same, none) = TextMarkup.apply("Hello there.", emphasis: ["absent"], pauseAfter: [])
    #expect(same == "Hello there." && none.isEmpty)
}

@Test func renderedTakeExportsAndRecallsLikeAnyOther() async throws {
    let (l, rc, job, binding, _) = try await setUp()
    try await rc.enqueue(jobID: job.id, actorBindingID: binding.id, segmentID: nil, engineID: "mock")
    await rc.drain()
    let take = try l.desk(job.id).takes[0]
    let out = l.root.appendingPathComponent("Delivered")
    let e = try l.exportTake(take.id, to: out)
    if case .found(let c, .metadata, _) = l.resolve(fileAt: out.appendingPathComponent(e.exportedName)) { #expect(c.takeID == take.id) }
    else { Issue.record("rendered take did not recall") }
}

@Test func launchRepairMarksUnfinishedRunsInterrupted() async throws {
    let (l, _, job, binding, _) = try await setUp()
    try await l.db.write { db in
        try RenderRun(id: UUID(), jobID: job.id, actorBindingID: binding.id, segmentID: nil, engineID: "qwen3-bench", state: "rendering",
                      requestJSON: "{}", resultJSON: nil, error: nil, takeID: nil, directionEventID: nil, createdAt: Date(),
                      startedAt: Date(), finishedAt: nil).insert(db)
    }
    let renders = l.root.appendingPathComponent("Library/\(job.id.uuidString.lowercased())/renders")
    try FileManager.default.createDirectory(at: renders, withIntermediateDirectories: true)
    try Data("half".utf8).write(to: renders.appendingPathComponent("x.wav"))
    let r = try l.repairAfterLaunch()
    #expect(r.interruptedRuns == 1 && r.removedTempFiles.contains("renders/x.wav"))
    #expect(try l.renderRuns(jobID: job.id)[0].state == "interrupted")
}

@Test func onlyExactDigitalSilenceIsTrimmedAndTheRawHashIsKept() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trim-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // 0.5 s tone + 2 s of exact zeros (24-bit mono 48 kHz)
    var tone = MockTone.wav(seconds: 0.5, frequency: 300)
    let f = try WAVReader.parse(tone)
    var audio = Data(tone[f.audioRange]); audio.append(Data(count: 48_000 * 3 * 2))
    var body = Data("WAVE".utf8)
    for (id, c) in [("fmt ", Data(tone[f.formatChunkRange])), ("data", audio)] {
        body.append(contentsOf: Array(id.utf8)); var n = UInt32(c.count); body.append(Data(bytes: &n, count: 4)); body.append(c)
    }
    tone = Data("RIFF".utf8); var n = UInt32(body.count); tone.append(Data(bytes: &n, count: 4)); tone.append(body)
    let u = dir.appendingPathComponent("a.wav"); try tone.write(to: u)
    let r = try DigitalSilence.trimTrailingZeros(at: u)
    #expect(abs(r.trimmedSeconds - 1.85) < 0.01 && r.rawSHA256 == SHA256.hex(tone) && r.note != nil)
    #expect(abs(try WAVReader.load(contentsOf: u).file.duration - 0.65) < 0.01)
    // quiet-but-not-zero tail is left alone
    let quiet = dir.appendingPathComponent("q.wav"); try MockTone.wav(seconds: 1, frequency: 300).write(to: quiet)
    #expect(try DigitalSilence.trimTrailingZeros(at: quiet).trimmedSeconds == 0)
}
