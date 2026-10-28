import Foundation
import GRDB
import BroadcastWave
#if canImport(Darwin)
import Darwin
#endif

public enum LibraryError: Error, LocalizedError, Equatable {
    case jobNotFound
    case takeNotFound
    case actorNotFound
    case segmentNotInJob
    case originalAudioMissing(String)
    case audioUnreadable(String)
    case fileWriteFailed(String)
    case emptyJobName

    public var errorDescription: String? {
        switch self {
        case .jobNotFound: "That job isn't in this library."
        case .takeNotFound: "That take isn't in this job."
        case .actorNotFound: "That actor isn't cast in this job."
        case .segmentNotInJob: "That line isn't part of this job's script."
        case .originalAudioMissing(let p): "The original take audio is missing from the library (\(p)). The take's record is intact; restore the file to export it."
        case .audioUnreadable(let why): "That audio can't be used: \(why)"
        case .fileWriteFailed(let why): "Couldn't write the audio file: \(why)"
        case .emptyJobName: "A job needs a name."
        }
    }
}

/// Where a Stage 1 take's audio came from. Nothing here is presented as a voice render.
public enum TakeAudioSource: Sendable {
    /// A WAV the director chose (e.g. an earlier bench render), copied byte-for-byte.
    case importedWAV(URL)
    /// A generated test tone — clearly labelled MOCK, for exercising the desk without any renderer.
    case mockTone(seconds: Double = 1.0, frequency: Double = 440)
}

public struct JobSummary: Sendable, Equatable, Identifiable {
    public let job: Job
    public let takeCount: Int
    public let approvedCount: Int
    public var id: UUID { job.id }
}

public struct JobDesk: Sendable {
    public let job: Job
    public let script: ScriptRevision?
    public let segments: [ScriptSegment]
    public let bindings: [JobActorBinding]
    public let takes: [Take]
    public let assets: [UUID: AudioAsset]
    public let exportsByTake: [UUID: [WAVExport]]
    public let missingAudio: Set<UUID>          // take IDs whose audio file is not on disk
    public let settings: JobSettings
}

public struct RecallCandidate: Sendable, Equatable, Identifiable {
    public let jobID: UUID
    public let takeID: UUID
    public let exportID: UUID?
    public let jobName: String
    public let actorName: String
    public let lineLabel: String
    public let takeNumber: Int
    public let takeName: String
    public let productionDate: String
    public let exportSummary: String?           // e.g. "48000 Hz · 24-bit · 1 ch, exported 2026-10-28"
    public var id: String { "\(takeID.uuidString)-\(exportID?.uuidString ?? "-")" }
}

public enum RecallMatch: String, Sendable {
    case metadata = "embedded JUJU identifiers"
    case bextMetadata = "embedded JUJU identifiers (BWF fallback)"
    case internalTakeFile = "JUJU take file name"
    case filename = "exported file name"
    case audioChecksum = "identical audio"
}

public enum RecallResolution: Sendable, Equatable {
    case found(RecallCandidate, via: RecallMatch, notes: [String])
    case chooseOne([RecallCandidate], notes: [String])
    case jobNotInLibrary(jobID: UUID, takeID: UUID)
    case takeNotInJob(jobID: UUID, takeID: UUID, jobName: String)
    case noMatch(notes: [String])
    case unreadable(String)
}

public struct RepairReport: Sendable, Equatable {
    public var removedTempFiles: [String] = []
    public var unreferencedTakeFiles: [String] = []   // reported, never deleted
}

public final class StudioLibrary: Sendable {
    public static let databaseFileName = "JUJU VO Studio.sqlite"
    public let root: URL
    public let db: DatabasePool
    public let appBuild: String
    let timeZone: TimeZone
    let clock: @Sendable () -> Date

    public init(root: URL, appBuild: String = "dev", timeZone: TimeZone = .current,
                clock: @escaping @Sendable () -> Date = { Date() }) throws {
        self.root = root.standardizedFileURL; self.appBuild = appBuild; self.timeZone = timeZone; self.clock = clock
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Library"), withIntermediateDirectories: true)
        self.db = try StudioSchema.open(at: root.appendingPathComponent(Self.databaseFileName))
    }

    // MARK: Paths

    func takesDir(_ jobID: UUID) -> URL {
        root.appendingPathComponent("Library").appendingPathComponent(jobID.uuidString.lowercased()).appendingPathComponent("takes")
    }
    public func url(for asset: AudioAsset) -> URL { root.appendingPathComponent(asset.relativePath) }

    // MARK: Jobs

    public func createJob(name: String, script: String) throws -> Job {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryError.emptyJobName }
        let now = clock()
        return try db.write { db in
            var job = Job(id: UUID(), name: trimmed, clientID: nil, brandID: nil, marketID: nil, createdAt: now,
                          lastOpenedAt: now, lastActivityAt: now, currentScriptRevisionID: nil, sourceJobID: nil,
                          status: "active", settingsSchemaVersion: JobSettings.schemaVersion, currentSettingsRevisionID: nil)
            try job.insert(db)
            let rev = try Self.insertScript(script, jobID: job.id, now: now, db: db)
            let settings = JobSettingsRevision(id: UUID(), jobID: job.id, schemaVersion: JobSettings.schemaVersion,
                                               canonicalSettingsJSON: JSON.encode(JobSettings()), createdAt: now,
                                               sourceJobSettingsRevisionID: nil, authoredBy: "director")
            try settings.insert(db)
            job.currentScriptRevisionID = rev.id; job.currentSettingsRevisionID = settings.id
            try job.update(db)
            try Self.log(db, "jobCreated", job: job.id, now: now, ["name": trimmed])
            return job
        }
    }

    /// Each non-empty line of the pasted script is a logical line, numbered from 1.
    static func insertScript(_ text: String, jobID: UUID, now: Date, db: Database) throws -> ScriptRevision {
        let rev = ScriptRevision(id: UUID(), jobID: jobID, rawText: text, createdAt: now)
        try rev.insert(db)
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for (i, line) in lines.enumerated() {
            try ScriptSegment(id: UUID(), revisionID: rev.id, stableLineNumber: i + 1, text: line, order: i, character: nil).insert(db)
        }
        return rev
    }

    /// Newest first by when the job was last opened or worked on.
    public func recentJobs(limit: Int = 200) throws -> [JobSummary] {
        try db.read { db in
            let jobs = try Job.filter(Column("status") == "active")
                .order(Column("lastOpenedAt").desc, Column("createdAt").desc).limit(limit).fetchAll(db)
            return try jobs.map { j in
                JobSummary(job: j,
                           takeCount: try Take.filter(Column("jobID") == j.id).fetchCount(db),
                           approvedCount: try Take.filter(Column("jobID") == j.id && Column("approvalState") == "approved").fetchCount(db))
            }
        }
    }

    public func markOpened(_ jobID: UUID) throws {
        let now = clock()
        try db.write { db in
            guard var job = try Job.fetchOne(db, key: jobID) else { throw LibraryError.jobNotFound }
            job.lastOpenedAt = now
            try job.update(db)
        }
    }

    public func desk(_ jobID: UUID) throws -> JobDesk {
        let (desk, paths) = try db.read { db -> (JobDesk, [(UUID, URL)]) in
            guard let job = try Job.fetchOne(db, key: jobID) else { throw LibraryError.jobNotFound }
            let script = try job.currentScriptRevisionID.flatMap { try ScriptRevision.fetchOne(db, key: $0) }
            let segments = try script.map {
                try ScriptSegment.filter(Column("revisionID") == $0.id).order(Column("order")).fetchAll(db)
            } ?? []
            let bindings = try JobActorBinding.filter(Column("jobID") == jobID).order(Column("createdAt")).fetchAll(db)
            let takes = try Take.filter(Column("jobID") == jobID)
                .order(Column("lineKey"), Column("actorDisplayNameSnapshot"), Column("perLineTakeNumber")).fetchAll(db)
            let assets = try AudioAsset.fetchAll(db, keys: takes.map(\.outputAssetID))
            let exports = try WAVExport.filter(Column("jobID") == jobID).order(Column("exportedAt")).fetchAll(db)
            let settingsJSON = try job.currentSettingsRevisionID.flatMap { try JobSettingsRevision.fetchOne(db, key: $0) }?.canonicalSettingsJSON
            let settings = settingsJSON.flatMap { try? JSON.decode(JobSettings.self, $0) } ?? JobSettings()
            let byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
            let paths = takes.compactMap { t in byID[t.outputAssetID].map { (t.id, self.url(for: $0)) } }
            return (JobDesk(job: job, script: script, segments: segments, bindings: bindings, takes: takes, assets: byID,
                            exportsByTake: Dictionary(grouping: exports, by: \.takeID), missingAudio: [], settings: settings), paths)
        }
        let missing = Set(paths.filter { !FileManager.default.fileExists(atPath: $0.1.path) }.map(\.0))
        return JobDesk(job: desk.job, script: desk.script, segments: desk.segments, bindings: desk.bindings, takes: desk.takes,
                       assets: desk.assets, exportsByTake: desk.exportsByTake, missingAudio: missing, settings: desk.settings)
    }

    // MARK: Cast

    /// Stage 1 actor: a placeholder voice master. No renderer, no reference audio, no rights claimed.
    @discardableResult
    public func addPlaceholderActor(jobID: UUID, displayName: String) throws -> JobActorBinding {
        let now = clock()
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return try db.write { db in
            guard try Job.exists(db, key: jobID) else { throw LibraryError.jobNotFound }
            let vm = VoiceMaster(id: UUID(), displayName: name.isEmpty ? "Actor" : name, origin: "placeholder", languageTag: nil,
                                 rightsNotes: "Placeholder for Stage 1 — no voice, no reference audio, no rights asserted.", createdAt: now)
            try vm.insert(db)
            let taken = Set(try JobActorBinding.filter(Column("jobID") == jobID).fetchAll(db).map { $0.fileToken.lowercased() })
            let binding = JobActorBinding(id: UUID(), jobID: jobID, voiceMasterID: vm.id, selectedRendererProfileID: nil,
                                          state: "audition", actorDisplayName: vm.displayName,
                                          fileToken: CanonicalNaming.uniqueActorToken(vm.displayName, taken: taken), notes: "", createdAt: now)
            try binding.insert(db)
            try Self.log(db, "actorCast", job: jobID, now: now, ["actor": vm.displayName, "voiceMasterOrigin": vm.origin])
            return binding
        }
    }

    // MARK: Takes

    /// Writes the audio (temp → validate → no-replace rename), then commits the records in one transaction.
    /// Every accepted take is kept; numbering is per job · actor · line and never reused.
    @discardableResult
    public func addTake(jobID: UUID, actorBindingID: UUID, segmentID: UUID?, audio source: TakeAudioSource) throws -> Take {
        let now = clock()
        let (bytes, provenance, note, sourceName) = try Self.audioBytes(for: source)
        let parsed: WAVFile
        do { parsed = try WAVReader.parse(bytes) } catch { throw LibraryError.audioUnreadable(error.localizedDescription) }

        let takeID = UUID(), assetID = UUID(), snapshotID = UUID()
        let dir = takesDir(jobID)
        let relative = "Library/\(jobID.uuidString.lowercased())/takes/\(takeID.uuidString.lowercased()).wav"
        let finalURL = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Self.atomicWrite(bytes, to: finalURL)
        let fileSHA = SHA256.hex(bytes)
        let dataSHA = SHA256.hex(bytes[parsed.audioRange])

        do {
            return try db.write { db in
                guard var job = try Job.fetchOne(db, key: jobID) else { throw LibraryError.jobNotFound }
                guard let binding = try JobActorBinding.fetchOne(db, key: actorBindingID), binding.jobID == jobID else { throw LibraryError.actorNotFound }
                guard let revID = job.currentScriptRevisionID, let settingsID = job.currentSettingsRevisionID,
                      let settingsRev = try JobSettingsRevision.fetchOne(db, key: settingsID) else { throw LibraryError.jobNotFound }
                var lineKey = 0, segmentText = (try ScriptRevision.fetchOne(db, key: revID))?.rawText ?? ""
                if let segmentID {
                    guard let seg = try ScriptSegment.fetchOne(db, key: segmentID), seg.revisionID == revID else { throw LibraryError.segmentNotInJob }
                    lineKey = seg.stableLineNumber; segmentText = seg.text
                }
                let previous = try Int.fetchOne(db, sql: "SELECT MAX(perLineTakeNumber) FROM take WHERE jobID = ? AND actorBindingID = ? AND lineKey = ?",
                                                arguments: [jobID, actorBindingID, lineKey]) ?? 0
                let number = previous + 1
                let date = CanonicalNaming.productionDate(now, timeZone: self.timeZone)
                let basename = CanonicalNaming.basename(jobToken: CanonicalNaming.token(job.name, fallback: "Job"),
                                                        actorToken: binding.fileToken, productionDate: date, lineKey: lineKey, takeNumber: number)
                let f = parsed.format
                let asset = AudioAsset(id: assetID, kind: "take", relativePath: relative, fileChecksum: fileSHA, dataChecksum: dataSHA,
                                       codec: f.isFloat ? "float" : "pcm", sampleRate: Int(f.sampleRate), bitsPerSample: Int(f.bitsPerSample),
                                       channels: Int(f.channels), duration: parsed.duration, captureSource: provenance, createdAt: now)
                try asset.insert(db)
                let vm = try VoiceMaster.fetchOne(db, key: binding.voiceMasterID)
                let jobSettings = (try? JSON.decode(JobSettings.self, settingsRev.canonicalSettingsJSON)) ?? JobSettings()
                let resolved = ResolvedTakeSettings(
                    provenance: provenance, provenanceNote: note, actor: binding.actorDisplayName,
                    voiceMasterOrigin: vm?.origin ?? "unknown", renderer: "none", job: jobSettings, sourceFileName: sourceName,
                    audio: .init(sampleRate: asset.sampleRate, bitsPerSample: asset.bitsPerSample, channels: asset.channels,
                                 codec: asset.codec, duration: asset.duration, dataSHA256: dataSHA))
                let take = Take(id: takeID, jobID: jobID, segmentID: segmentID, lineKey: lineKey, perLineTakeNumber: number,
                                actorBindingID: actorBindingID, voiceMasterID: binding.voiceMasterID,
                                actorDisplayNameSnapshot: binding.actorDisplayName,
                                rendererSnapshotJSON: JSON.encode(["renderer": "none", "provenance": provenance]),
                                scriptRevisionID: revID, segmentTextSnapshot: segmentText, outputAssetID: assetID,
                                provenance: provenance, status: "accepted", approvalState: "none", approvedAssetID: nil,
                                approvedScriptRevisionID: nil, approvedAt: nil, canonicalBasename: basename, productionDate: date,
                                takeSettingsSnapshotID: snapshotID, createdAt: now)
                try take.insert(db)
                try TakeSettingsSnapshot(id: snapshotID, takeID: takeID, jobSettingsRevisionID: settingsID,
                                         resolvedSettingsJSON: JSON.encode(resolved), scriptRevisionID: revID,
                                         voiceMasterID: binding.voiceMasterID, rendererProfileID: nil, engineBuild: nil,
                                         modelRevision: nil, conditioningJSON: nil, randomSeed: nil,
                                         outputFormatJSON: JSON.encode(resolved.audio), appBuild: self.appBuild, createdAt: now).insert(db)
                job.lastActivityAt = now
                try job.update(db)
                try Self.log(db, "takeAdded", job: jobID, take: takeID, now: now, ["name": basename, "provenance": provenance])
                return take
            }
        } catch {
            try? FileManager.default.removeItem(at: finalURL)   // ours, never referenced: safe to remove
            throw error
        }
    }

    static func audioBytes(for source: TakeAudioSource) throws -> (Data, String, String, String?) {
        switch source {
        case .importedWAV(let url):
            let data: Data
            do { data = try Data(contentsOf: url) } catch { throw LibraryError.audioUnreadable(error.localizedDescription) }
            return (data, "importedWAV", "Imported WAV copied byte-for-byte; not rendered by JUJU.", url.lastPathComponent)
        case .mockTone(let seconds, let frequency):
            return (MockTone.wav(seconds: seconds, frequency: frequency), "mockFixture",
                    "MOCK test tone generated by JUJU VO Studio Stage 1 — not a voice, not a render.", nil)
        }
    }

    /// Approval names the exact audio asset and script revision, never just "Take 02". Audio is untouched.
    public func setApproval(takeID: UUID, approved: Bool) throws {
        let now = clock()
        try db.write { db in
            guard var take = try Take.fetchOne(db, key: takeID) else { throw LibraryError.takeNotFound }
            if approved {
                take.approvalState = "approved"; take.approvedAssetID = take.outputAssetID
                take.approvedScriptRevisionID = take.scriptRevisionID; take.approvedAt = now
            } else {
                take.approvalState = "none"; take.approvedAssetID = nil; take.approvedScriptRevisionID = nil; take.approvedAt = nil
            }
            try take.update(db)
            try Self.log(db, approved ? "takeApproved" : "takeApprovalCleared", job: take.jobID, take: takeID, now: now,
                         ["asset": take.outputAssetID.uuidString.lowercased()])
        }
    }

    // MARK: Export

    /// Exports a take as BWF with the job/take/export UUIDs, into `folder`. Never overwrites: a clash gets "-2", "-3"….
    @discardableResult
    public func exportTake(_ takeID: UUID, to folder: URL) throws -> WAVExport {
        let now = clock()
        let (take, asset, job) = try db.read { db -> (Take, AudioAsset, Job) in
            guard let t = try Take.fetchOne(db, key: takeID) else { throw LibraryError.takeNotFound }
            guard let a = try AudioAsset.fetchOne(db, key: t.outputAssetID), let j = try Job.fetchOne(db, key: t.jobID) else { throw LibraryError.takeNotFound }
            return (t, a, j)
        }
        let source = url(for: asset)
        guard FileManager.default.fileExists(atPath: source.path) else { throw LibraryError.originalAudioMissing(asset.relativePath) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let exportID = UUID()
        let info = BWFExportInfo(identifiers: .init(jobID: take.jobID, takeID: take.id, exportID: exportID),
                                 project: job.name, scene: CanonicalNaming.lineToken(take.lineKey),
                                 take: take.perLineTakeNumber, origination: take.createdAt, timeZone: timeZone)
        var name = take.canonicalBasename + ".wav"
        var receipt: BWFExportReceipt?
        for n in 1...999 {
            if n > 1 { name = "\(take.canonicalBasename)-\(n).wav" }
            do { receipt = try BWFWriter.export(sourceWAV: source, to: folder.appendingPathComponent(name), info: info); break }
            catch BWFWriteError.destinationExists { continue }
        }
        guard let receipt else { throw LibraryError.fileWriteFailed("no free file name in \(folder.path)") }
        let export = WAVExport(id: exportID, jobID: take.jobID, takeID: take.id, sourceAudioAssetID: asset.id, exportedName: name,
                               lastKnownPath: receipt.destination.path, exportedFileChecksum: receipt.fileSHA256,
                               audioDataChecksum: receipt.audioSHA256, exportedAt: now, takeSettingsSnapshotID: take.takeSettingsSnapshotID,
                               metadataSchemaVersion: JUJURecallIdentifiers.currentMetadataVersion,
                               byteFormat: receipt.format.isFloat ? "float" : "pcm", sampleRate: Int(receipt.format.sampleRate),
                               bitDepth: Int(receipt.format.bitsPerSample), channelCount: Int(receipt.format.channels))
        try db.write { db in
            try export.insert(db)
            try WAVRecallIndexEntry(id: UUID(), jobID: take.jobID, takeID: take.id, wavExportID: exportID,
                                    canonicalExportFilename: name, basenameKey: CanonicalNaming.lookupKey(forFileName: name),
                                    candidateAudioChecksum: receipt.audioSHA256,
                                    metadataVersion: JUJURecallIdentifiers.currentMetadataVersion).insert(db)
            try Self.log(db, "takeExported", job: take.jobID, take: take.id, now: now, ["name": name, "export": exportID.uuidString.lowercased()])
        }
        return export
    }

    // MARK: Recall (read-only: never renders, approves, or changes a job)

    public func resolve(fileAt url: URL) -> RecallResolution {
        let data: Data, file: WAVFile
        do { (data, file) = try WAVReader.load(contentsOf: url) } catch {
            return .unreadable((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        var notes: [String] = []
        do {
            switch file.juju {
            case .valid(let ids, let source):
                let job = try db.read { try Job.fetchOne($0, key: ids.jobID) }
                guard let job else { return .jobNotInLibrary(jobID: ids.jobID, takeID: ids.takeID) }
                let take = try db.read { db in try Take.filter(Column("id") == ids.takeID && Column("jobID") == ids.jobID).fetchOne(db) }
                guard take != nil else { return .takeNotInJob(jobID: ids.jobID, takeID: ids.takeID, jobName: job.name) }
                var exportID = ids.exportID
                if let e = ids.exportID {
                    let export = try db.read { try WAVExport.fetchOne($0, key: e) }
                    if let export, export.takeID != ids.takeID {
                        notes.append("The file's export ID belongs to a different take, so its embedded IDs were not trusted.")
                        break
                    }
                    if export == nil { notes.append("This export isn't recorded in this library (exported from another copy?); the take itself is here."); exportID = nil }
                }
                return .found(try candidate(takeID: ids.takeID, exportID: exportID), via: source == .ixml ? .metadata : .bextMetadata, notes: notes)
            case .absent: break
            case .unsupportedVersion(let v): notes.append("The file's JUJU metadata is version \(v), newer than this app understands; matching by name instead.")
            case .malformed(let why): notes.append("The file's JUJU metadata is damaged (\(why)); matching by name instead.")
            case .conflicting(let why): notes.append("The file's JUJU metadata contradicts itself (\(why)); matching by name instead.")
            }

            let fileName = url.lastPathComponent
            // An internal library take file is named by its take UUID.
            if let takeID = UUID(uuidString: String(fileName.dropLast(fileName.lowercased().hasSuffix(".wav") ? 4 : 0))),
               try db.read({ try Take.exists($0, key: takeID) }) {
                return .found(try candidate(takeID: takeID, exportID: nil), via: .internalTakeFile, notes: notes)
            }
            // Exact (normalised, case-folded) file-name match — never fuzzy.
            let key = CanonicalNaming.lookupKey(forFileName: fileName)
            let dataSHA = SHA256.hex(data[file.audioRange])
            let byName: [(UUID, UUID?)] = try db.read { db in
                let idx = try WAVRecallIndexEntry.filter(Column("basenameKey") == key).fetchAll(db)
                var out = idx.map { ($0.takeID, Optional($0.wavExportID)) }
                for t in try Take.fetchAll(db) where CanonicalNaming.lookupKey(forFileName: t.canonicalBasename) == key {
                    if !out.contains(where: { $0.0 == t.id }) { out.append((t.id, nil)) }
                }
                return out
            }
            if !byName.isEmpty {
                let candidates = try distinctTakes(byName, preferChecksum: dataSHA)
                if candidates.count == 1 { return .found(candidates[0], via: .filename, notes: notes) }
                return .chooseOne(candidates, notes: notes + ["More than one take has this file name."])
            }
            // Identical audio bytes (a convenience, not a fingerprint).
            let byAudio: [(UUID, UUID?)] = try db.read { db in
                var out = try WAVRecallIndexEntry.filter(Column("candidateAudioChecksum") == dataSHA).fetchAll(db).map { ($0.takeID, Optional($0.wavExportID)) }
                let assets = try AudioAsset.filter(Column("dataChecksum") == dataSHA).fetchAll(db).map(\.id)
                for t in try Take.filter(assets.contains(Column("outputAssetID"))).fetchAll(db) where !out.contains(where: { $0.0 == t.id }) {
                    out.append((t.id, nil))
                }
                return out
            }
            if !byAudio.isEmpty {
                let candidates = try distinctTakes(byAudio, preferChecksum: dataSHA)
                if candidates.count == 1 { return .found(candidates[0], via: .audioChecksum, notes: notes) }
                return .chooseOne(candidates, notes: notes + ["The same audio belongs to more than one take."])
            }
            return .noMatch(notes: notes)
        } catch {
            return .unreadable("Library lookup failed: \(error.localizedDescription)")
        }
    }

    /// One candidate per take; if several exports of a take matched, prefer the one whose audio matches the file.
    func distinctTakes(_ pairs: [(UUID, UUID?)], preferChecksum sha: String) throws -> [RecallCandidate] {
        var seen: [UUID: UUID?] = [:]
        var order: [UUID] = []
        for (takeID, exportID) in pairs {
            if seen[takeID] == nil { seen[takeID] = exportID; order.append(takeID); continue }
            if let e = exportID, try db.read({ try WAVExport.fetchOne($0, key: e) })?.audioDataChecksum == sha { seen[takeID] = e }
        }
        return try order.map { try candidate(takeID: $0, exportID: seen[$0] ?? nil) }
    }

    public func candidate(takeID: UUID, exportID: UUID?) throws -> RecallCandidate {
        try db.read { db in
            guard let t = try Take.fetchOne(db, key: takeID), let j = try Job.fetchOne(db, key: t.jobID) else { throw LibraryError.takeNotFound }
            let e = try exportID.flatMap { try WAVExport.fetchOne(db, key: $0) }
            return RecallCandidate(jobID: j.id, takeID: t.id, exportID: e?.id, jobName: j.name, actorName: t.actorDisplayNameSnapshot,
                                   lineLabel: t.lineLabel, takeNumber: t.perLineTakeNumber, takeName: t.canonicalBasename,
                                   productionDate: t.productionDate,
                                   exportSummary: e.map { "\($0.exportedName) · \($0.sampleRate) Hz · \($0.bitDepth)-bit · \($0.channelCount) ch" })
        }
    }

    /// Search saved export and take names (no disk crawling).
    public func searchDeliveredNames(_ query: String, limit: Int = 50) throws -> [RecallCandidate] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 2 else { return [] }
        let pairs: [(UUID, UUID?)] = try db.read { db in
            var out = try WAVRecallIndexEntry.fetchAll(db).filter { $0.canonicalExportFilename.lowercased().contains(q) }.map { ($0.takeID, Optional($0.wavExportID)) }
            for t in try Take.fetchAll(db) where t.canonicalBasename.lowercased().contains(q) && !out.contains(where: { $0.0 == t.id }) { out.append((t.id, nil)) }
            return out
        }
        return Array(try distinctTakes(pairs, preferChecksum: "").prefix(limit))
    }

    // MARK: New job from settings

    /// New identity, fresh numbering and approvals; settings copied as a new revision linked to the source; cast re-bound
    /// to the same voice masters. The source job and its audio are not touched.
    public func newJob(fromSettingsOf sourceJobID: UUID, name: String, copyScript: Bool) throws -> Job {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryError.emptyJobName }
        let now = clock()
        return try db.write { db in
            guard let source = try Job.fetchOne(db, key: sourceJobID) else { throw LibraryError.jobNotFound }
            var job = Job(id: UUID(), name: trimmed, clientID: source.clientID, brandID: source.brandID, marketID: source.marketID,
                          createdAt: now, lastOpenedAt: now, lastActivityAt: now, currentScriptRevisionID: nil, sourceJobID: source.id,
                          status: "active", settingsSchemaVersion: JobSettings.schemaVersion, currentSettingsRevisionID: nil)
            try job.insert(db)
            let script = copyScript ? (try source.currentScriptRevisionID.flatMap { try ScriptRevision.fetchOne(db, key: $0) }?.rawText ?? "") : ""
            let rev = try Self.insertScript(script, jobID: job.id, now: now, db: db)
            let srcSettings = try source.currentSettingsRevisionID.flatMap { try JobSettingsRevision.fetchOne(db, key: $0) }
            let settings = JobSettingsRevision(id: UUID(), jobID: job.id, schemaVersion: srcSettings?.schemaVersion ?? JobSettings.schemaVersion,
                                               canonicalSettingsJSON: srcSettings?.canonicalSettingsJSON ?? JSON.encode(JobSettings()),
                                               createdAt: now, sourceJobSettingsRevisionID: srcSettings?.id, authoredBy: "newFromSettings")
            try settings.insert(db)
            for b in try JobActorBinding.filter(Column("jobID") == source.id).order(Column("createdAt")).fetchAll(db) {
                try JobActorBinding(id: UUID(), jobID: job.id, voiceMasterID: b.voiceMasterID, selectedRendererProfileID: b.selectedRendererProfileID,
                                    state: "audition", actorDisplayName: b.actorDisplayName, fileToken: b.fileToken,
                                    notes: "", createdAt: now).insert(db)
            }
            job.currentScriptRevisionID = rev.id; job.currentSettingsRevisionID = settings.id
            try job.update(db)
            try Self.log(db, "jobCreatedFromSettings", job: job.id, now: now, ["source": source.id.uuidString.lowercased(), "name": trimmed])
            return job
        }
    }

    // MARK: Crash repair

    /// Removes our own leftover temp files; reports (never deletes) take files the database doesn't know.
    public func repairAfterLaunch() throws -> RepairReport {
        var report = RepairReport()
        let fm = FileManager.default
        let lib = root.appendingPathComponent("Library")
        let known = Set(try db.read { try String.fetchAll($0, sql: "SELECT relativePath FROM audioAsset") })
        for jobDir in (try? fm.contentsOfDirectory(at: lib, includingPropertiesForKeys: nil)) ?? [] {
            let takes = jobDir.appendingPathComponent("takes")
            for f in (try? fm.contentsOfDirectory(atPath: takes.path)) ?? [] {
                if f.hasPrefix(".juju-tmp-") {
                    try? fm.removeItem(at: takes.appendingPathComponent(f)); report.removedTempFiles.append(f)
                } else if f.lowercased().hasSuffix(".wav") {
                    let rel = "Library/\(jobDir.lastPathComponent)/takes/\(f)"
                    if !known.contains(rel) { report.unreferencedTakeFiles.append(rel) }
                }
            }
        }
        return report
    }

    // MARK: Helpers

    static func atomicWrite(_ bytes: Data, to final: URL) throws {
        let fm = FileManager.default
        let temp = final.deletingLastPathComponent().appendingPathComponent(".juju-tmp-\(UUID().uuidString).wav")
        defer { try? fm.removeItem(at: temp) }
        do {
            try bytes.write(to: temp)
            let h = try FileHandle(forUpdating: temp); try h.synchronize(); try h.close()
            guard try Data(contentsOf: temp) == bytes else { throw LibraryError.fileWriteFailed("verification mismatch") }
        } catch let e as LibraryError { throw e } catch { throw LibraryError.fileWriteFailed(error.localizedDescription) }
        if link(temp.path, final.path) != 0 { throw LibraryError.fileWriteFailed(String(cString: strerror(errno))) }
    }

    static func log(_ db: Database, _ kind: String, job: UUID?, take: UUID? = nil, now: Date, _ payload: [String: String]) throws {
        try StudioEvent(id: UUID(), jobID: job, takeID: take, kind: kind, payloadJSON: JSON.encode(payload), createdAt: now).insert(db)
    }
}

/// Generated test tone for Stage 1 ("mock-labelled"). 48 kHz / 24-bit mono sine with 10 ms fades.
public enum MockTone {
    public static func wav(seconds: Double, frequency: Double, sampleRate: Int = 48_000) -> Data {
        let frames = max(1, Int(seconds * Double(sampleRate)))
        let fade = sampleRate / 100
        var audio = Data(capacity: frames * 3)
        for i in 0..<frames {
            let env = min(1.0, Double(min(i, frames - 1 - i)) / Double(fade))
            let v = Int32(sin(2 * .pi * frequency * Double(i) / Double(sampleRate)) * env * 0.25 * 8_388_607)
            audio.append(UInt8(truncatingIfNeeded: v)); audio.append(UInt8(truncatingIfNeeded: v >> 8)); audio.append(UInt8(truncatingIfNeeded: v >> 16))
        }
        let fmt = WAVFormat.canonicalChunk(sampleRate: UInt32(sampleRate), channels: 1, bitsPerSample: 24)
        var body = Data("WAVE".utf8)
        for (id, c) in [("fmt ", fmt), ("data", audio)] {
            body.append(contentsOf: Array(id.utf8))
            var n = UInt32(c.count); body.append(Data(bytes: &n, count: 4)); body.append(c)
            if c.count % 2 == 1 { body.append(0) }
        }
        var out = Data("RIFF".utf8); var n = UInt32(body.count); out.append(Data(bytes: &n, count: 4)); out.append(body)
        return out
    }
}
