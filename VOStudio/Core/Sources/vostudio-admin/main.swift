import Foundation
import VOStudioCore

// vostudio-admin <library> add-voice <name> <reference.wav> <transcript.txt|-> <lang> [label] [rights…]
// vostudio-admin <library> add-reference <voice-name> <reference.wav> <transcript.txt|-> <label>
// vostudio-admin <library> voices
// vostudio-admin <library> qwen-smoke [voice-name] [variation]     — real render through the bench Qwen worker
// vostudio-admin <library> use                                     — point JUJU VO Studio at this library
let a = CommandLine.arguments
func fail(_ s: String) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(1) }
guard a.count >= 3 else { fail("usage: vostudio-admin <library> <command> …") }
let root = URL(fileURLWithPath: a[1])
let lib: StudioLibrary
do { lib = try StudioLibrary(root: root, appBuild: "vostudio-admin") } catch { fail("open library: \(error)") }
func text(_ p: String) -> String? { p == "-" ? nil : (try? String(contentsOfFile: p, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) }

switch a[2] {
case "add-voice":
    guard a.count >= 7 else { fail("add-voice <name> <wav> <transcript|-> <lang> [label] [rights]") }
    if let existing = try lib.voices().first(where: { $0.voice.displayName == a[3] }) { print("exists: \(existing.voice.id)"); exit(0) }
    let v = try lib.addVoice(displayName: a[3], origin: "hostCloned", languageTag: a[6],
                             rightsNotes: a.count > 8 ? a[8...].joined(separator: " ") : "Operator-supplied reference; local use.",
                             referenceWAV: URL(fileURLWithPath: a[4]), referenceLabel: a.count > 7 ? a[7] : "reference 1", transcript: text(a[5]))
    print("added voice \(v.voice.displayName) \(v.voice.id) ref \(v.references[0].sha256)")
case "add-reference":
    guard a.count >= 7, let v = try lib.voices().first(where: { $0.voice.displayName == a[3] }) else { fail("add-reference <voice> <wav> <transcript|-> <label>") }
    if v.references.contains(where: { $0.label == a[6] }) { print("exists"); exit(0) }
    let r = try lib.addReference(voiceMasterID: v.voice.id, label: a[6], referenceWAV: URL(fileURLWithPath: a[4]), transcript: text(a[5]))
    print("added reference \(r.label) \(r.sha256)")
case "voices":
    for v in try lib.voices() {
        print("\(v.voice.displayName)  [\(v.voice.origin), \(v.voice.languageTag ?? "?")]  \(v.voice.id)")
        for r in v.references { print("   · \(r.label)  \(String(format: "%.1f", r.durationSeconds)) s  transcript:\(r.transcript != nil)  \(r.sha256.prefix(12))") }
    }
case "qwen-smoke":
    let name = a.count > 3 ? a[3] : nil
    let variation = PerformanceDirection.Variation(rawValue: a.count > 4 ? a[4] : "standard") ?? .standard
    guard let voice = try lib.voices().first(where: { name == nil || $0.voice.displayName == name }) else { fail("no voice") }
    let engine = QwenBenchActorEngine(benchRoot: QwenBenchActorEngine.defaultBenchRoot)
    let h = await engine.health(); print("health: \(h.status) — \(h.message)")
    guard h.status != .unavailable else { exit(2) }
    let t0 = Date(); try await engine.warmUp(); print(String(format: "warm-up %.1f s", Date().timeIntervalSince(t0)))
    let job = try lib.createJob(name: "Qwen Smoke", script: "Today only at our store.\nDaz gel. It's a dose of common sense.")
    let b = try lib.cast(voiceMasterID: voice.voice.id, into: job.id)
    let rc = RenderCoordinator(library: lib); await rc.register(engine)
    let seg = try lib.desk(job.id).segments
    let stream = await rc.updates()
    let watcher = Task { for await u in stream { print("  run \(u.run.id.uuidString.prefix(8)) → \(u.run.state)\(u.run.error.map { " — \($0)" } ?? "")") } }
    for s in seg {
        let t = Date()
        try await rc.enqueue(jobID: job.id, actorBindingID: b.id, segmentID: s.id, engineID: engine.descriptor.id, direction: .init(variation: variation))
        await rc.drain(); print(String(format: "  line %d rendered in %.1f s", s.stableLineNumber, Date().timeIntervalSince(t)))
    }
    watcher.cancel()
    for take in try lib.desk(job.id).takes {
        let asset = try lib.desk(job.id).assets[take.outputAssetID]!
        print("take \(take.canonicalBasename)  \(String(format: "%.2f", asset.duration)) s  \(asset.sampleRate) Hz/\(asset.bitsPerSample)-bit  provenance=\(take.provenance)")
        print("   file \(lib.url(for: asset).path)")
        if let s = try lib.snapshot(for: take) { print("   model \(s.modelRevision ?? "-")  seed \(s.randomSeed ?? 0)") }
    }
    for r in try lib.renderRuns(jobID: job.id) where r.state != "succeeded" { print("NOT OK run \(r.id): \(r.state) \(r.error ?? "")"); exit(3) }
    await engine.shutdown()
    print("job \(job.id.uuidString.lowercased())")
case "use":
    let d = UserDefaults(suiteName: "tv.juju.vostudio")!
    d.set(try root.bookmarkData(), forKey: "libraryRootBookmark"); d.synchronize(); print("JUJU VO Studio now uses \(root.path)")
default: fail("unknown command \(a[2])")
}
