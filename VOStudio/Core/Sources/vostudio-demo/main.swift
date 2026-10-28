import Foundation
import VOStudioCore

// vostudio-demo <library-folder> <export-folder> [--use]
// Creates "Job A" with actor Jane and four MOCK-tone takes on line 3, approves take 4 and exports it
// (plus a stripped-metadata copy named canonically). With --use, points JUJU VO Studio at the library.
let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: vostudio-demo <library-folder> <export-folder> [--use]"); exit(2) }
let root = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
do {
    let lib = try StudioLibrary(root: root, appBuild: "vostudio-demo")
    let job = try lib.createJob(name: "Job A", script: "Today only at our store.\nDiscover something new.\nLenor. Fresh for longer.")
    let jane = try lib.addPlaceholderActor(jobID: job.id, displayName: "Jane")
    let line3 = try lib.desk(job.id).segments.first { $0.stableLineNumber == 3 }!
    var take: Take!
    for i in 0..<4 { take = try lib.addTake(jobID: job.id, actorBindingID: jane.id, segmentID: line3.id, audio: .mockTone(seconds: 1.5, frequency: 330 + Double(i) * 55)) }
    try lib.setApproval(takeID: take.id, approved: true)
    let e = try lib.exportTake(take.id, to: out)
    print("job=\(job.id.uuidString.lowercased()) take=\(take.id.uuidString.lowercased()) export=\(e.id.uuidString.lowercased())")
    print("exported: \(e.lastKnownPath)")
    if args.contains("--use") {
        let defaults = UserDefaults(suiteName: "tv.juju.vostudio")!
        defaults.set(try root.bookmarkData(), forKey: "libraryRootBookmark")
        defaults.synchronize()
        print("JUJU VO Studio now uses library \(root.path)")
    }
} catch { print("error: \(error)"); exit(1) }
