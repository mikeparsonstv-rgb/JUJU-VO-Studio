import Foundation
import GRDB
import BroadcastWave

/// Reference recording a voice is cloned from. Local-only: the path never leaves this Mac and is never
/// written into an exported WAV. Hash pins exactly which audio conditioned each take.
public struct VoiceReference: Codable, Sendable, Equatable, Identifiable, StudioRecord {
    public static let databaseTableName = "voiceReference"
    public var id: UUID
    public var voiceMasterID: UUID
    public var label: String
    public var localPath: String
    public var sha256: String
    public var transcript: String?
    public var languageTag: String
    public var durationSeconds: Double
    public var createdAt: Date
}

/// One render request, persisted before the engine is called (brief §4.2: render returns a run ID first).
public struct RenderRun: Codable, Sendable, Equatable, Identifiable, StudioRecord {
    public static let databaseTableName = "renderRun"
    public var id: UUID
    public var jobID: UUID
    public var actorBindingID: UUID
    public var segmentID: UUID?
    public var engineID: String
    public var state: String                 // queued | rendering | succeeded | failed | interrupted
    public var requestJSON: String
    public var resultJSON: String?
    public var error: String?
    public var takeID: UUID?
    public var directionEventID: UUID?
    public var createdAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?
    public var isFinished: Bool { ["succeeded", "failed", "interrupted"].contains(state) }
}

extension StudioSchema {
    static func registerStage2(_ m: inout DatabaseMigrator) {
        m.registerMigration("v2-stage2-voices-renders") { db in
            try db.create(table: "voiceReference") { t in
                t.primaryKey("id", .blob)
                t.column("voiceMasterID", .blob).notNull().references("voiceMaster")
                t.column("label", .text).notNull()
                t.column("localPath", .text).notNull()
                t.column("sha256", .text).notNull()
                t.column("transcript", .text)
                t.column("languageTag", .text).notNull()
                t.column("durationSeconds", .double).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "renderRun") { t in
                t.primaryKey("id", .blob)
                t.column("jobID", .blob).notNull().references("job")
                t.column("actorBindingID", .blob).notNull().references("jobActorBinding")
                t.column("segmentID", .blob).references("scriptSegment")
                t.column("engineID", .text).notNull()
                t.column("state", .text).notNull()
                    .check(sql: "state IN ('queued','rendering','succeeded','failed','interrupted')")
                t.column("requestJSON", .text).notNull()
                t.column("resultJSON", .text)
                t.column("error", .text)
                t.column("takeID", .blob).references("take")
                t.column("directionEventID", .blob).references("directionEvent")
                t.column("createdAt", .datetime).notNull()
                t.column("startedAt", .datetime)
                t.column("finishedAt", .datetime)
            }
            try db.create(index: "renderRun_job", on: "renderRun", columns: ["jobID", "createdAt"])
            try db.execute(sql: """
                CREATE TRIGGER voice_reference_immutable BEFORE UPDATE ON voiceReference
                WHEN NEW.sha256 IS NOT OLD.sha256 OR NEW.localPath IS NOT OLD.localPath OR NEW.voiceMasterID IS NOT OLD.voiceMasterID
                BEGIN SELECT RAISE(ABORT, 'JUJU: a voice reference is immutable; add a new one'); END;
                CREATE TRIGGER render_run_finished_is_final BEFORE UPDATE ON renderRun
                WHEN OLD.state IN ('succeeded','failed','interrupted')
                BEGIN SELECT RAISE(ABORT, 'JUJU: a finished render run is final'); END;
                """)
        }
    }
}

public struct VoiceSummary: Sendable, Equatable, Identifiable {
    public let voice: VoiceMaster
    public let references: [VoiceReference]
    public var id: UUID { voice.id }
}

extension StudioLibrary {
    /// Adds a cloned/licensed voice with one reference recording. The WAV is hashed and its path kept local.
    @discardableResult
    public func addVoice(displayName: String, origin: String, languageTag: String, rightsNotes: String,
                         referenceWAV: URL, referenceLabel: String = "reference 1", transcript: String?) throws -> VoiceSummary {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LibraryError.audioUnreadable("a voice needs a name") }
        guard ["hostCloned", "licensed", "generated"].contains(origin) else { throw LibraryError.audioUnreadable("unknown voice origin \(origin)") }
        let (data, file): (Data, WAVFile)
        do { (data, file) = try WAVReader.load(contentsOf: referenceWAV) } catch {
            throw LibraryError.audioUnreadable("reference: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
        }
        let now = clock()
        return try db.write { db in
            let vm = VoiceMaster(id: UUID(), displayName: name, origin: origin, languageTag: languageTag,
                                 rightsNotes: rightsNotes, createdAt: now)
            try vm.insert(db)
            let ref = VoiceReference(id: UUID(), voiceMasterID: vm.id, label: referenceLabel,
                                     localPath: referenceWAV.standardizedFileURL.path, sha256: SHA256.hex(data),
                                     transcript: transcript?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                                     languageTag: languageTag, durationSeconds: file.duration, createdAt: now)
            try ref.insert(db)
            try Self.log(db, "voiceAdded", job: nil, now: now, ["voice": name, "origin": origin, "referenceSHA256": ref.sha256])
            return VoiceSummary(voice: vm, references: [ref])
        }
    }

    @discardableResult
    public func addReference(voiceMasterID: UUID, label: String, referenceWAV: URL, transcript: String?) throws -> VoiceReference {
        let (data, file) = try WAVReader.load(contentsOf: referenceWAV)
        let now = clock()
        return try db.write { db in
            guard let vm = try VoiceMaster.fetchOne(db, key: voiceMasterID) else { throw LibraryError.actorNotFound }
            let ref = VoiceReference(id: UUID(), voiceMasterID: vm.id, label: label, localPath: referenceWAV.standardizedFileURL.path,
                                     sha256: SHA256.hex(data), transcript: transcript?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                                     languageTag: vm.languageTag ?? "en-GB", durationSeconds: file.duration, createdAt: now)
            try ref.insert(db)
            return ref
        }
    }

    /// Voices that can actually perform (placeholders excluded).
    public func voices() throws -> [VoiceSummary] {
        try db.read { db in
            let vms = try VoiceMaster.filter(Column("origin") != "placeholder").order(Column("createdAt")).fetchAll(db)
            return try vms.map { vm in
                VoiceSummary(voice: vm, references: try VoiceReference.filter(Column("voiceMasterID") == vm.id).order(Column("createdAt")).fetchAll(db))
            }
        }
    }

    /// Casts an existing voice into a job. The voice's name is authoritative and is not renamed.
    @discardableResult
    public func cast(voiceMasterID: UUID, into jobID: UUID) throws -> JobActorBinding {
        let now = clock()
        return try db.write { db in
            guard try Job.exists(db, key: jobID) else { throw LibraryError.jobNotFound }
            guard let vm = try VoiceMaster.fetchOne(db, key: voiceMasterID) else { throw LibraryError.actorNotFound }
            let existing = try JobActorBinding.filter(Column("jobID") == jobID).fetchAll(db)
            if let already = existing.first(where: { $0.voiceMasterID == voiceMasterID }) { return already }
            let binding = JobActorBinding(id: UUID(), jobID: jobID, voiceMasterID: vm.id, selectedRendererProfileID: nil,
                                          state: "audition", actorDisplayName: vm.displayName,
                                          fileToken: CanonicalNaming.uniqueActorToken(vm.displayName, taken: Set(existing.map { $0.fileToken.lowercased() })),
                                          notes: "", createdAt: now)
            try binding.insert(db)
            try Self.log(db, "actorCast", job: jobID, now: now, ["actor": vm.displayName, "voiceMasterOrigin": vm.origin])
            return binding
        }
    }

    public func voice(for bindingID: UUID) throws -> (JobActorBinding, VoiceMaster, [VoiceReference]) {
        try db.read { db in
            guard let b = try JobActorBinding.fetchOne(db, key: bindingID), let vm = try VoiceMaster.fetchOne(db, key: b.voiceMasterID)
            else { throw LibraryError.actorNotFound }
            return (b, vm, try VoiceReference.filter(Column("voiceMasterID") == vm.id).order(Column("createdAt")).fetchAll(db))
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
