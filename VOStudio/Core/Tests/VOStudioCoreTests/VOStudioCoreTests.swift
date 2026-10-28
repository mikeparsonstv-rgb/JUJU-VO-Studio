import Foundation
import Testing
import GRDB
import BroadcastWave
@testable import VOStudioCore

// All tests are model-free: audio is a generated MOCK tone or a fixture WAV.

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_793_200_000)   // 2026-10-28, whole seconds
    func now() -> Date { lock.lock(); defer { lock.unlock() }; t += 1; return t }
}

private func tempDir(_ tag: String = "") throws -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("vostudio-\(tag)\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private func makeLibrary() throws -> StudioLibrary {
    let c = Clock()
    return try StudioLibrary(root: try tempDir("lib-"), appBuild: "test", timeZone: TimeZone(identifier: "Europe/London")!, clock: c.now)
}

/// Job "Job A", Jane, three lines; Jane has takes 1…4 on line 3. Returns (lib, job, jane binding, line-3 take 4).
private func jobAJaneLine3Take4(_ lib: StudioLibrary) throws -> (Job, JobActorBinding, Take) {
    let job = try lib.createJob(name: "Job A", script: "Today only at our store.\n\nDiscover something new.\nLenor. Fresh for longer.")
    let jane = try lib.addPlaceholderActor(jobID: job.id, displayName: "Jane")
    let line3 = try lib.desk(job.id).segments.first { $0.stableLineNumber == 3 }!
    var last: Take!
    for i in 0..<4 { last = try lib.addTake(jobID: job.id, actorBindingID: jane.id, segmentID: line3.id, audio: .mockTone(seconds: 0.2, frequency: 300 + Double(i) * 50)) }
    return (job, jane, last)
}

private func tableCounts(_ lib: StudioLibrary) throws -> [String: Int] {
    try lib.db.read { db in
        var out: [String: Int] = [:]
        for t in ["job", "take", "audioAsset", "wavExport", "wavRecallIndex", "studioEvent", "jobActorBinding", "jobSettingsRevision"] {
            out[t] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(t)")
        }
        out["approved"] = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM take WHERE approvalState='approved'")
        return out
    }
}

private func sha(_ url: URL) throws -> String { SHA256.hex(try Data(contentsOf: url)) }

private func strip(_ url: URL, to dest: URL) throws {
    let (d, f) = try WAVReader.load(contentsOf: url)
    var body = Data("WAVE".utf8)
    for (id, c) in [("fmt ", d[f.formatChunkRange]), ("data", d[f.audioRange])] {
        body.append(contentsOf: Array(id.utf8)); var n = UInt32(c.count); body.append(Data(bytes: &n, count: 4)); body.append(c)
        if c.count % 2 == 1 { body.append(0) }
    }
    var out = Data("RIFF".utf8); var n = UInt32(body.count); out.append(Data(bytes: &n, count: 4)); out.append(body)
    try out.write(to: dest)
}

// MARK: - Jobs, script, naming

@Test func scriptLinesAreLogicalAndNumberedFromOne() throws {
    let lib = try makeLibrary()
    let job = try lib.createJob(name: "Lenor Autumn DE", script: "  Line one.\n\n\nLine two.\r\nLine three.  ")
    let d = try lib.desk(job.id)
    #expect(d.segments.map(\.stableLineNumber) == [1, 2, 3])
    #expect(d.segments.map(\.text) == ["Line one.", "Line two.", "Line three."])
    #expect(d.settings == JobSettings())
}

@Test func canonicalNamesFollowTheBrief() throws {
    let lib = try makeLibrary()
    let (_, _, take) = try jobAJaneLine3Take4(lib)
    #expect(take.canonicalBasename == "JobA-Jane-2026-10-28-Line03-Take04")
    #expect(take.perLineTakeNumber == 4 && take.lineKey == 3 && take.productionDate == "2026-10-28")
    #expect(CanonicalNaming.token("Lenor Autumn DE", fallback: "Job") == "LenorAutumnDE")
    #expect(CanonicalNaming.token("Zoë Ångström", fallback: "Actor") == "ZoeAngstrom")
    #expect(CanonicalNaming.token("???", fallback: "Actor") == "Actor")
    #expect(CanonicalNaming.uniqueActorToken("Anna", taken: ["anna"]) == "Anna2")
}

@Test func sameNamedActorsGetDistinctFileTokensAndFullReadIsNamed() throws {
    let lib = try makeLibrary()
    let job = try lib.createJob(name: "Autumn Campaign", script: "One.")
    let a1 = try lib.addPlaceholderActor(jobID: job.id, displayName: "Anna")
    let a2 = try lib.addPlaceholderActor(jobID: job.id, displayName: "Anna")
    #expect(a1.fileToken == "Anna" && a2.fileToken == "Anna2")
    let t1 = try lib.addTake(jobID: job.id, actorBindingID: a1.id, segmentID: nil, audio: .mockTone())
    let t2 = try lib.addTake(jobID: job.id, actorBindingID: a2.id, segmentID: nil, audio: .mockTone())
    #expect(t1.canonicalBasename == "AutumnCampaign-Anna-2026-10-28-FullRead-Take01")
    #expect(t2.canonicalBasename == "AutumnCampaign-Anna2-2026-10-28-FullRead-Take01")
}

@Test func recentJobsAreNewestFirstAndReopenUpdatesRecency() throws {
    let lib = try makeLibrary()
    let a = try lib.createJob(name: "A", script: "x"), b = try lib.createJob(name: "B", script: "x")
    #expect(try lib.recentJobs().map(\.job.id) == [b.id, a.id])
    try lib.markOpened(a.id)
    #expect(try lib.recentJobs().map(\.job.id) == [a.id, b.id])
}

// MARK: - Takes are written atomically and are immutable

@Test func importedTakeIsCopiedByteForByteUnderItsUUID() throws {
    let lib = try makeLibrary()
    let job = try lib.createJob(name: "Job A", script: "Hello.")
    let jane = try lib.addPlaceholderActor(jobID: job.id, displayName: "Jane")
    let src = try tempDir().appendingPathComponent("qwen_run1_BHM01.wav")
    try MockTone.wav(seconds: 0.3, frequency: 220).write(to: src)
    let take = try lib.addTake(jobID: job.id, actorBindingID: jane.id, segmentID: nil, audio: .importedWAV(src))
    let d = try lib.desk(job.id)
    let asset = d.assets[take.outputAssetID]!
    #expect(asset.relativePath == "Library/\(job.id.uuidString.lowercased())/takes/\(take.id.uuidString.lowercased()).wav")
    #expect(try sha(lib.url(for: asset)) == (try sha(src)))
    #expect(take.provenance == "importedWAV" && asset.captureSource == "importedWAV")
    let snap = try lib.db.read { try TakeSettingsSnapshot.fetchOne($0, key: take.takeSettingsSnapshotID) }!
    #expect(snap.takeID == take.id && snap.resolvedSettingsJSON.contains("\"renderer\":\"none\""))
    #expect(snap.resolvedSettingsJSON.contains("qwen_run1_BHM01.wav"))
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: lib.url(for: asset).deletingLastPathComponent().path).filter { $0.hasPrefix(".juju-tmp") }
    #expect(leftovers.isEmpty)
}

@Test func takeAudioAndIdentityCannotBeChangedOrDeleted() throws {
    let lib = try makeLibrary()
    let (_, _, take) = try jobAJaneLine3Take4(lib)
    #expect(throws: (any Error).self) {
        try lib.db.write { try $0.execute(sql: "UPDATE take SET outputAssetID = ? WHERE id = ?", arguments: [UUID(), take.id]) }
    }
    #expect(throws: (any Error).self) {
        try lib.db.write { try $0.execute(sql: "UPDATE take SET actorDisplayNameSnapshot = 'Lucy' WHERE id = ?", arguments: [take.id]) }
    }
    #expect(throws: (any Error).self) { try lib.db.write { try $0.execute(sql: "DELETE FROM take") } }
    #expect(throws: (any Error).self) { try lib.db.write { try $0.execute(sql: "DELETE FROM audioAsset") } }
    #expect(throws: (any Error).self) { try lib.db.write { try $0.execute(sql: "DELETE FROM studioEvent") } }
}

@Test func unreadableAudioIsRefusedAndLeavesNothingBehind() throws {
    let lib = try makeLibrary()
    let job = try lib.createJob(name: "J", script: "x")
    let a = try lib.addPlaceholderActor(jobID: job.id, displayName: "A")
    let bad = try tempDir().appendingPathComponent("notes.wav")
    try Data("this is not audio".utf8).write(to: bad)
    #expect(throws: (any Error).self) { try lib.addTake(jobID: job.id, actorBindingID: a.id, segmentID: nil, audio: .importedWAV(bad)) }
    #expect(try tableCounts(lib)["take"] == 0)
}

@Test func approvalNamesTheAssetAndScriptRevisionAndLeavesAudioAlone() throws {
    let lib = try makeLibrary()
    let (job, _, take) = try jobAJaneLine3Take4(lib)
    let asset = try lib.desk(job.id).assets[take.outputAssetID]!
    let before = try sha(lib.url(for: asset))
    try lib.setApproval(takeID: take.id, approved: true)
    let t = try lib.desk(job.id).takes.first { $0.id == take.id }!
    #expect(t.isApproved && t.approvedAssetID == take.outputAssetID && t.approvedScriptRevisionID == take.scriptRevisionID)
    #expect(try sha(lib.url(for: asset)) == before)
    #expect(throws: (any Error).self) {   // database refuses an approval that names no asset
        try lib.db.write { try $0.execute(sql: "UPDATE take SET approvalState='none', approvedAssetID=NULL WHERE id=?", arguments: [take.id])
                           try $0.execute(sql: "UPDATE take SET approvalState='approved' WHERE id=?", arguments: [take.id]) }
    }
}

// MARK: - Export + recall (§7A.4)

@Test func exportEmbedsExactIDsAndIsIndexed() throws {
    let lib = try makeLibrary()
    let (job, _, take) = try jobAJaneLine3Take4(lib)
    let out = try tempDir("out-")
    let e = try lib.exportTake(take.id, to: out)
    #expect(e.exportedName == "JobA-Jane-2026-10-28-Line03-Take04.wav")
    let parsed = try WAVReader.load(contentsOf: out.appendingPathComponent(e.exportedName)).file
    #expect(parsed.juju == .valid(.init(jobID: job.id, takeID: take.id, exportID: e.id), source: .ixml))
    let asset = try lib.desk(job.id).assets[take.outputAssetID]!
    #expect(e.audioDataChecksum == asset.dataChecksum)   // audio bytes unchanged by export
    #expect(try lib.db.read { try WAVRecallIndexEntry.fetchCount($0) } == 1)
}

@Test func secondExportIsADistinctExportOfTheSameTakeAndNeverOverwrites() throws {
    let lib = try makeLibrary()
    let (_, _, take) = try jobAJaneLine3Take4(lib)
    let out = try tempDir("out-")
    let e1 = try lib.exportTake(take.id, to: out)
    let first = try sha(out.appendingPathComponent(e1.exportedName))
    let e2 = try lib.exportTake(take.id, to: out)
    #expect(e2.exportedName == "JobA-Jane-2026-10-28-Line03-Take04-2.wav")
    #expect(e1.id != e2.id && e1.takeID == e2.takeID)
    #expect(try sha(out.appendingPathComponent(e1.exportedName)) == first)
    if case .found(let c, .metadata, _) = lib.resolve(fileAt: out.appendingPathComponent(e2.exportedName)) {
        #expect(c.takeID == take.id && c.exportID == e2.id)
    } else { Issue.record("second export did not resolve by metadata") }
}

@Test func droppedExportOpensTheExactTakeEvenWhenRenamed() throws {
    let lib = try makeLibrary()
    let (job, _, take) = try jobAJaneLine3Take4(lib)
    let out = try tempDir("out-")
    let e = try lib.exportTake(take.id, to: out)
    let renamed = out.appendingPathComponent("FINAL mix v2 (approved).wav")
    try FileManager.default.moveItem(at: out.appendingPathComponent(e.exportedName), to: renamed)
    guard case .found(let c, .metadata, let notes) = lib.resolve(fileAt: renamed) else { Issue.record("not found"); return }
    #expect(c.jobID == job.id && c.takeID == take.id && c.exportID == e.id && notes.isEmpty)
    #expect(c.actorName == "Jane" && c.lineLabel == "Line 03" && c.takeNumber == 4 && c.jobName == "Job A")
}

@Test func strippedMetadataStillResolvesByCanonicalFileName() throws {
    let lib = try makeLibrary()
    let (_, _, take) = try jobAJaneLine3Take4(lib)
    let out = try tempDir("out-"), elsewhere = try tempDir("dl-")
    let e = try lib.exportTake(take.id, to: out)
    let stripped = elsewhere.appendingPathComponent(e.exportedName)       // e.g. bounced through a DAW
    try strip(out.appendingPathComponent(e.exportedName), to: stripped)
    #expect(try WAVReader.load(contentsOf: stripped).file.juju == .absent)
    guard case .found(let c, .filename, _) = lib.resolve(fileAt: stripped) else { Issue.record("not found by name"); return }
    #expect(c.takeID == take.id)
    // case-insensitive volume / different extension case
    let upper = try tempDir("uc-").appendingPathComponent("JOBA-JANE-2026-10-28-LINE03-TAKE04.WAV")
    try FileManager.default.copyItem(at: stripped, to: upper)
    if case .found(let c2, .filename, _) = lib.resolve(fileAt: upper) { #expect(c2.takeID == take.id) } else { Issue.record("case-folded name") }
}

@Test func strippedAndRenamedFallsBackToIdenticalAudio() throws {
    let lib = try makeLibrary()
    let (_, _, take) = try jobAJaneLine3Take4(lib)
    let out = try tempDir("out-")
    let e = try lib.exportTake(take.id, to: out)
    let anon = out.appendingPathComponent("audio_final.wav")
    try strip(out.appendingPathComponent(e.exportedName), to: anon)
    guard case .found(let c, .audioChecksum, _) = lib.resolve(fileAt: anon) else { Issue.record("not found by audio"); return }
    #expect(c.takeID == take.id)
}

@Test func internalTakeFileResolves() throws {
    let lib = try makeLibrary()
    let (job, _, take) = try jobAJaneLine3Take4(lib)
    let asset = try lib.desk(job.id).assets[take.outputAssetID]!
    guard case .found(let c, .internalTakeFile, _) = lib.resolve(fileAt: lib.url(for: asset)) else { Issue.record("internal file"); return }
    #expect(c.takeID == take.id)
}

@Test func duplicateFileNamesAcrossJobsAskInsteadOfGuessing() throws {
    let lib = try makeLibrary()
    let (_, _, t1) = try jobAJaneLine3Take4(lib)
    let (_, _, t2) = try jobAJaneLine3Take4(lib)            // second "Job A", same day, same actor/line/take
    #expect(t1.canonicalBasename == t2.canonicalBasename)
    let out1 = try tempDir("o1-"), out2 = try tempDir("o2-")
    let e1 = try lib.exportTake(t1.id, to: out1); _ = try lib.exportTake(t2.id, to: out2)
    let stripped = try tempDir("s-").appendingPathComponent(e1.exportedName)
    // different audio from either take so the checksum can't decide; name only
    try MockTone.wav(seconds: 0.1, frequency: 999).write(to: stripped)
    guard case .chooseOne(let cs, _) = lib.resolve(fileAt: stripped) else { Issue.record("expected chooser"); return }
    #expect(Set(cs.map(\.takeID)) == [t1.id, t2.id])
}

@Test func unknownAndDamagedFilesFailSafely() throws {
    let lib = try makeLibrary()
    _ = try jobAJaneLine3Take4(lib)
    let dir = try tempDir()
    let stranger = dir.appendingPathComponent("someone_elses_vo.wav")
    try MockTone.wav(seconds: 0.1, frequency: 123).write(to: stranger)
    #expect(lib.resolve(fileAt: stranger) == .noMatch(notes: []))
    let junk = dir.appendingPathComponent("broken.wav")
    var bytes = MockTone.wav(seconds: 0.1, frequency: 123)
    bytes.replaceSubrange(40..<44, with: [0xFF, 0xFF, 0xFF, 0xFF])
    try bytes.write(to: junk)
    if case .unreadable = lib.resolve(fileAt: junk) {} else { Issue.record("huge chunk length should be unreadable") }
    if case .unreadable = lib.resolve(fileAt: dir.appendingPathComponent("does-not-exist.wav")) {} else { Issue.record("missing file / no permission") }
}

@Test func fileFromAnotherLibraryReportsMissingJob() throws {
    let other = try makeLibrary(), here = try makeLibrary()
    let (job, _, take) = try jobAJaneLine3Take4(other)
    let e = try other.exportTake(take.id, to: try tempDir("o-"))
    #expect(here.resolve(fileAt: URL(fileURLWithPath: e.lastKnownPath)) == .jobNotInLibrary(jobID: job.id, takeID: take.id))
}

@Test func badOrNewerMetadataIsNotTrustedButNameStillWorks() throws {
    let lib = try makeLibrary()
    let (job, _, take) = try jobAJaneLine3Take4(lib)
    let dir = try tempDir()
    let fmt = WAVFormat.canonicalChunk(sampleRate: 48_000, channels: 1, bitsPerSample: 16)
    func file(_ user: String, name: String) throws -> URL {
        let x = Data("<BWFXML><USER>\(user)</USER></BWFXML>".utf8)
        var body = Data("WAVE".utf8)
        for (id, c) in [("fmt ", fmt), ("iXML", x), ("data", Data(count: 96))] {
            body.append(contentsOf: Array(id.utf8)); var n = UInt32(c.count); body.append(Data(bytes: &n, count: 4)); body.append(c)
            if c.count % 2 == 1 { body.append(0) }
        }
        var out = Data("RIFF".utf8); var n = UInt32(body.count); out.append(Data(bytes: &n, count: 4)); out.append(body)
        let u = dir.appendingPathComponent(name); try out.write(to: u); return u
    }
    let j = job.id.uuidString, t = take.id.uuidString
    let newer = try file("JUJU_JOB_UUID=\(j)\nJUJU_TAKE_UUID=\(t)\nJUJU_METADATA_VERSION=9", name: take.canonicalBasename + ".wav")
    guard case .found(let c, .filename, let notes) = lib.resolve(fileAt: newer) else { Issue.record("newer version"); return }
    #expect(c.takeID == take.id && notes.first?.contains("version 9") == true)
    let bad = try file("JUJU_JOB_UUID=\(j)\nJUJU_TAKE_UUID=nope\nJUJU_METADATA_VERSION=1", name: "x.wav")
    if case .noMatch(let n) = lib.resolve(fileAt: bad) { #expect(n.first?.contains("damaged") == true) } else { Issue.record("bad uuid") }
    let wrongTake = try file("JUJU_JOB_UUID=\(j)\nJUJU_TAKE_UUID=\(UUID().uuidString)\nJUJU_METADATA_VERSION=1", name: "y.wav")
    if case .takeNotInJob(let jid, _, let name) = lib.resolve(fileAt: wrongTake) { #expect(jid == job.id && name == "Job A") } else { Issue.record("take not in job") }
}

@Test func resolvingNeverChangesTheLibrary() throws {
    let lib = try makeLibrary()
    let (_, _, take) = try jobAJaneLine3Take4(lib)
    let out = try tempDir("out-")
    let e = try lib.exportTake(take.id, to: out)
    let before = try tableCounts(lib)
    for _ in 0..<3 { _ = lib.resolve(fileAt: out.appendingPathComponent(e.exportedName)) }
    #expect(try tableCounts(lib) == before)
}

@Test func missingOriginalAudioKeepsTheTakeBrowsableAndExportFailsClearly() throws {
    let lib = try makeLibrary()
    let (job, _, take) = try jobAJaneLine3Take4(lib)
    let out = try tempDir("out-")
    let e = try lib.exportTake(take.id, to: out)
    let asset = try lib.desk(job.id).assets[take.outputAssetID]!
    try FileManager.default.removeItem(at: lib.url(for: asset))
    #expect(try lib.desk(job.id).missingAudio == [take.id])
    if case .found(let c, .metadata, _) = lib.resolve(fileAt: out.appendingPathComponent(e.exportedName)) { #expect(c.takeID == take.id) }
    else { Issue.record("recall should still find the take record") }
    #expect(throws: LibraryError.originalAudioMissing(asset.relativePath)) { try lib.exportTake(take.id, to: out) }
}

// MARK: - Make changes today / New job with these settings

@Test func makingChangesAddsANewTakeAndLeavesTheOriginalAlone() throws {
    let lib = try makeLibrary()
    let (job, jane, take) = try jobAJaneLine3Take4(lib)
    try lib.setApproval(takeID: take.id, approved: true)
    let asset = try lib.desk(job.id).assets[take.outputAssetID]!
    let before = try sha(lib.url(for: asset))
    let pickup = try lib.addTake(jobID: job.id, actorBindingID: jane.id, segmentID: take.segmentID, audio: .mockTone())
    #expect(pickup.perLineTakeNumber == 5 && pickup.canonicalBasename.hasSuffix("Line03-Take05"))
    #expect(try sha(lib.url(for: asset)) == before)
    #expect(try lib.desk(job.id).takes.first { $0.id == take.id }!.isApproved)
}

@Test func newJobWithTheseSettingsHasNewIdentityAndNoInheritedApprovals() throws {
    let lib = try makeLibrary()
    let (source, _, take) = try jobAJaneLine3Take4(lib)
    try lib.setApproval(takeID: take.id, approved: true)
    let before = try lib.desk(source.id)
    let fresh = try lib.newJob(fromSettingsOf: source.id, name: "Job A — Spring", copyScript: true)
    let d = try lib.desk(fresh.id)
    #expect(fresh.id != source.id && fresh.sourceJobID == source.id)
    #expect(d.takes.isEmpty && d.segments.map(\.text) == before.segments.map(\.text))
    #expect(d.bindings.map(\.actorDisplayName) == ["Jane"] && d.bindings[0].voiceMasterID == before.bindings[0].voiceMasterID)
    #expect(d.bindings[0].id != before.bindings[0].id && d.bindings[0].state == "audition")
    let rev = try lib.db.read { try JobSettingsRevision.fetchOne($0, key: fresh.currentSettingsRevisionID!) }!
    #expect(rev.sourceJobSettingsRevisionID == source.currentSettingsRevisionID)
    let after = try lib.desk(source.id)
    #expect(after.takes == before.takes && after.job.name == "Job A")
    let first = try lib.addTake(jobID: fresh.id, actorBindingID: d.bindings[0].id, segmentID: d.segments[2].id, audio: .mockTone())
    #expect(first.perLineTakeNumber == 1)   // fresh numbering
    let noScript = try lib.newJob(fromSettingsOf: source.id, name: "Job A — blank", copyScript: false)
    #expect(try lib.desk(noScript.id).segments.isEmpty)
}

// MARK: - Crash repair, direction source

@Test func launchRepairRemovesTempFilesAndOnlyReportsUnknownTakes() throws {
    let lib = try makeLibrary()
    let (job, _, _) = try jobAJaneLine3Take4(lib)
    let takes = lib.takesDir(job.id)
    try Data("partial".utf8).write(to: takes.appendingPathComponent(".juju-tmp-crash.wav"))
    let stray = takes.appendingPathComponent("\(UUID().uuidString.lowercased()).wav")
    try MockTone.wav(seconds: 0.1, frequency: 200).write(to: stray)
    let r = try lib.repairAfterLaunch()
    #expect(r.removedTempFiles == [".juju-tmp-crash.wav"])
    #expect(r.unreferencedTakeFiles.count == 1 && FileManager.default.fileExists(atPath: stray.path))
}

@Test func directionEventsCarryTheirSource() throws {
    let lib = try makeLibrary()
    let job = try lib.createJob(name: "J", script: "x")
    try lib.db.write { db in
        try DirectionEvent(id: UUID(), jobID: job.id, sessionID: nil, targetSegmentIDsJSON: "[]", transcript: "warmer", intent: nil,
                           source: "conversationDerived", rawAudioAssetID: nil, proposedAction: nil, confirmedAction: nil, createdAt: Date()).insert(db)
    }
    #expect(throws: (any Error).self) {
        try lib.db.write { db in
            try DirectionEvent(id: UUID(), jobID: job.id, sessionID: nil, targetSegmentIDsJSON: "[]", transcript: "x", intent: nil,
                               source: "vibes", rawAudioAssetID: nil, proposedAction: nil, confirmedAction: nil, createdAt: Date()).insert(db)
        }
    }
}

@Test func filenameSearchFindsDeliveredNames() throws {
    let lib = try makeLibrary()
    let (_, _, take) = try jobAJaneLine3Take4(lib)
    _ = try lib.exportTake(take.id, to: try tempDir("o-"))
    #expect(try lib.searchDeliveredNames("line03-take04").map(\.takeID) == [take.id])
    #expect(try lib.searchDeliveredNames("x").isEmpty)
}

@Test func waveformPeaksAreBoundedAndNonEmpty() throws {
    let lib = try makeLibrary()
    let (job, _, take) = try jobAJaneLine3Take4(lib)
    let peaks = WaveformPeaks.compute(fileAt: lib.url(for: try lib.desk(job.id).assets[take.outputAssetID]!), buckets: 100)
    #expect(peaks.count == 100 && peaks.max()! > 0.2 && peaks.max()! <= 1)
}
