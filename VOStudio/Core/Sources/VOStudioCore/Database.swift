import Foundation
import GRDB

/// Shared record conformance. UUIDs use GRDB's native 16-byte BLOB encoding everywhere (records, keys and
/// query arguments agree without per-call conversion); the WAV metadata carries the canonical text form.
public protocol StudioRecord: FetchableRecord, PersistableRecord {}

extension Client { public static let databaseTableName = "client" }
extension Brand { public static let databaseTableName = "brand" }
extension Market { public static let databaseTableName = "market" }
extension Job { public static let databaseTableName = "job" }
extension ScriptRevision { public static let databaseTableName = "scriptRevision" }
extension ScriptSegment { public static let databaseTableName = "scriptSegment" }
extension VoiceMaster { public static let databaseTableName = "voiceMaster" }
extension RendererProfile { public static let databaseTableName = "rendererProfile" }
extension JobActorBinding { public static let databaseTableName = "jobActorBinding" }
extension AudioAsset { public static let databaseTableName = "audioAsset" }
extension Take { public static let databaseTableName = "take" }
extension JobSettingsRevision { public static let databaseTableName = "jobSettingsRevision" }
extension TakeSettingsSnapshot { public static let databaseTableName = "takeSettingsSnapshot" }
extension WAVExport { public static let databaseTableName = "wavExport" }
extension WAVRecallIndexEntry { public static let databaseTableName = "wavRecallIndex" }
extension EngineerSession { public static let databaseTableName = "engineerSession" }
extension DirectionEvent { public static let databaseTableName = "directionEvent" }
extension StudioEvent { public static let databaseTableName = "studioEvent" }

public enum StudioSchema {
    public static let currentVersion = 1

    public static func migrator() -> DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1-stage1") { db in
            try db.create(table: "client") { t in
                t.primaryKey("id", .blob); t.column("displayName", .text).notNull()
                t.column("aliasesJSON", .text).notNull().defaults(to: "[]"); t.column("notes", .text).notNull().defaults(to: "")
            }
            try db.create(table: "brand") { t in
                t.primaryKey("id", .blob); t.column("clientID", .blob).references("client")
                t.column("displayName", .text).notNull(); t.column("aliasesJSON", .text).notNull().defaults(to: "[]")
            }
            try db.create(table: "market") { t in
                t.primaryKey("id", .blob); t.column("countryCode", .text).notNull(); t.column("languageTag", .text).notNull()
                t.column("dialectTag", .text); t.column("notes", .text).notNull().defaults(to: "")
            }
            try db.create(table: "job") { t in
                t.primaryKey("id", .blob)
                t.column("name", .text).notNull()
                t.column("clientID", .blob).references("client")
                t.column("brandID", .blob).references("brand")
                t.column("marketID", .blob).references("market")
                t.column("createdAt", .datetime).notNull()
                t.column("lastOpenedAt", .datetime).notNull()
                t.column("lastActivityAt", .datetime).notNull()
                t.column("currentScriptRevisionID", .blob)
                t.column("sourceJobID", .blob).references("job")
                t.column("status", .text).notNull()
                t.column("settingsSchemaVersion", .integer).notNull()
                t.column("currentSettingsRevisionID", .blob)
            }
            try db.create(index: "job_recency", on: "job", columns: ["lastOpenedAt"])
            try db.create(table: "scriptRevision") { t in
                t.primaryKey("id", .blob); t.column("jobID", .blob).notNull().references("job")
                t.column("rawText", .text).notNull(); t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "scriptSegment") { t in
                t.primaryKey("id", .blob); t.column("revisionID", .blob).notNull().references("scriptRevision")
                t.column("stableLineNumber", .integer).notNull(); t.column("text", .text).notNull()
                t.column("order", .integer).notNull(); t.column("character", .text)
                t.uniqueKey(["revisionID", "stableLineNumber"])
            }
            try db.create(table: "voiceMaster") { t in
                t.primaryKey("id", .blob); t.column("displayName", .text).notNull(); t.column("origin", .text).notNull()
                t.column("languageTag", .text); t.column("rightsNotes", .text).notNull(); t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "rendererProfile") { t in
                t.primaryKey("id", .blob); t.column("voiceMasterID", .blob).notNull().references("voiceMaster")
                t.column("engineID", .blob).notNull(); t.column("backendVoiceID", .blob); t.column("modelVersion", .text)
                t.column("conditioningJSON", .text); t.column("state", .text).notNull(); t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "jobActorBinding") { t in
                t.primaryKey("id", .blob); t.column("jobID", .blob).notNull().references("job")
                t.column("voiceMasterID", .blob).notNull().references("voiceMaster")
                t.column("selectedRendererProfileID", .blob).references("rendererProfile")
                t.column("state", .text).notNull(); t.column("actorDisplayName", .text).notNull()
                t.column("fileToken", .text).notNull(); t.column("notes", .text).notNull(); t.column("createdAt", .datetime).notNull()
                t.uniqueKey(["jobID", "fileToken"])
            }
            try db.create(table: "audioAsset") { t in
                t.primaryKey("id", .blob); t.column("kind", .text).notNull()
                t.column("relativePath", .text).notNull().unique()
                t.column("fileChecksum", .text).notNull(); t.column("dataChecksum", .text).notNull()
                t.column("codec", .text).notNull(); t.column("sampleRate", .integer).notNull()
                t.column("bitsPerSample", .integer).notNull(); t.column("channels", .integer).notNull()
                t.column("duration", .double).notNull(); t.column("captureSource", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "audioAsset_data", on: "audioAsset", columns: ["dataChecksum"])
            try db.create(table: "jobSettingsRevision") { t in
                t.primaryKey("id", .blob); t.column("jobID", .blob).notNull().references("job")
                t.column("schemaVersion", .integer).notNull(); t.column("canonicalSettingsJSON", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("sourceJobSettingsRevisionID", .blob).references("jobSettingsRevision")
                t.column("authoredBy", .text).notNull()
            }
            try db.create(table: "take") { t in
                t.primaryKey("id", .blob)
                t.column("jobID", .blob).notNull().references("job")
                t.column("segmentID", .blob).references("scriptSegment")
                t.column("lineKey", .integer).notNull()
                t.column("perLineTakeNumber", .integer).notNull()
                t.column("actorBindingID", .blob).notNull().references("jobActorBinding")
                t.column("voiceMasterID", .blob).notNull().references("voiceMaster")
                t.column("actorDisplayNameSnapshot", .text).notNull()
                t.column("rendererSnapshotJSON", .text).notNull()
                t.column("scriptRevisionID", .blob).notNull().references("scriptRevision")
                t.column("segmentTextSnapshot", .text).notNull()
                t.column("outputAssetID", .blob).notNull().unique().references("audioAsset")
                t.column("provenance", .text).notNull()
                t.column("status", .text).notNull()
                t.column("approvalState", .text).notNull()
                t.column("approvedAssetID", .blob).references("audioAsset")
                t.column("approvedScriptRevisionID", .blob).references("scriptRevision")
                t.column("approvedAt", .datetime)
                t.column("canonicalBasename", .text).notNull()
                t.column("productionDate", .text).notNull()
                t.column("takeSettingsSnapshotID", .blob).notNull()   // circular with snapshot.takeID; set in one transaction
                t.column("createdAt", .datetime).notNull()
                t.uniqueKey(["jobID", "actorBindingID", "lineKey", "perLineTakeNumber"])
            }
            try db.create(index: "take_job", on: "take", columns: ["jobID", "lineKey"])
            try db.create(table: "takeSettingsSnapshot") { t in
                t.primaryKey("id", .blob)
                t.column("takeID", .blob).notNull().unique().references("take", deferred: true)
                t.column("jobSettingsRevisionID", .blob).notNull().references("jobSettingsRevision")
                t.column("resolvedSettingsJSON", .text).notNull()
                t.column("scriptRevisionID", .blob).notNull().references("scriptRevision")
                t.column("voiceMasterID", .blob).notNull().references("voiceMaster")
                t.column("rendererProfileID", .blob).references("rendererProfile")
                t.column("engineBuild", .text); t.column("modelRevision", .text); t.column("conditioningJSON", .text)
                t.column("randomSeed", .integer); t.column("outputFormatJSON", .text).notNull()
                t.column("appBuild", .text).notNull(); t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "wavExport") { t in
                t.primaryKey("id", .blob)
                t.column("jobID", .blob).notNull().references("job")
                t.column("takeID", .blob).notNull().references("take")
                t.column("sourceAudioAssetID", .blob).notNull().references("audioAsset")
                t.column("exportedName", .text).notNull(); t.column("lastKnownPath", .text).notNull()
                t.column("exportedFileChecksum", .text).notNull(); t.column("audioDataChecksum", .text).notNull()
                t.column("exportedAt", .datetime).notNull()
                t.column("takeSettingsSnapshotID", .blob).notNull().references("takeSettingsSnapshot")
                t.column("metadataSchemaVersion", .integer).notNull(); t.column("byteFormat", .text).notNull()
                t.column("sampleRate", .integer).notNull(); t.column("bitDepth", .integer).notNull()
                t.column("channelCount", .integer).notNull()
            }
            try db.create(table: "wavRecallIndex") { t in
                t.primaryKey("id", .blob)
                t.column("jobID", .blob).notNull().references("job")
                t.column("takeID", .blob).notNull().references("take")
                t.column("wavExportID", .blob).notNull().references("wavExport")
                t.column("canonicalExportFilename", .text).notNull()
                t.column("basenameKey", .text).notNull()
                t.column("candidateAudioChecksum", .text).notNull()
                t.column("metadataVersion", .integer).notNull()
            }
            try db.create(index: "recall_basename", on: "wavRecallIndex", columns: ["basenameKey"])
            try db.create(index: "recall_checksum", on: "wavRecallIndex", columns: ["candidateAudioChecksum"])
            try db.create(index: "recall_take", on: "wavRecallIndex", columns: ["takeID"])
            try db.create(table: "engineerSession") { t in
                t.primaryKey("id", .blob); t.column("jobID", .blob).notNull().references("job")
                t.column("mode", .text).notNull(); t.column("provider", .text).notNull()
                t.column("startedAt", .datetime).notNull(); t.column("lastStatus", .text).notNull()
            }
            try db.create(table: "directionEvent") { t in
                t.primaryKey("id", .blob); t.column("jobID", .blob).notNull().references("job")
                t.column("sessionID", .blob).references("engineerSession")
                t.column("targetSegmentIDsJSON", .text).notNull(); t.column("transcript", .text).notNull()
                t.column("intent", .text)
                t.column("source", .text).notNull().check(sql: "source IN ('guideDerived','conversationDerived','manualText')")
                t.column("rawAudioAssetID", .blob).references("audioAsset")
                t.column("proposedAction", .text); t.column("confirmedAction", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "studioEvent") { t in
                t.primaryKey("id", .blob); t.column("jobID", .blob); t.column("takeID", .blob)
                t.column("kind", .text).notNull(); t.column("payloadJSON", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            // Immutability, enforced by the database rather than by convention.
            try db.execute(sql: """
                CREATE TRIGGER take_audio_immutable BEFORE UPDATE ON take
                WHEN NEW.id IS NOT OLD.id OR NEW.jobID IS NOT OLD.jobID OR NEW.segmentID IS NOT OLD.segmentID OR NEW.lineKey IS NOT OLD.lineKey OR NEW.perLineTakeNumber IS NOT OLD.perLineTakeNumber OR NEW.actorBindingID IS NOT OLD.actorBindingID OR NEW.voiceMasterID IS NOT OLD.voiceMasterID OR NEW.actorDisplayNameSnapshot IS NOT OLD.actorDisplayNameSnapshot OR NEW.rendererSnapshotJSON IS NOT OLD.rendererSnapshotJSON OR NEW.scriptRevisionID IS NOT OLD.scriptRevisionID OR NEW.segmentTextSnapshot IS NOT OLD.segmentTextSnapshot OR NEW.outputAssetID IS NOT OLD.outputAssetID OR NEW.provenance IS NOT OLD.provenance OR NEW.canonicalBasename IS NOT OLD.canonicalBasename OR NEW.productionDate IS NOT OLD.productionDate OR NEW.takeSettingsSnapshotID IS NOT OLD.takeSettingsSnapshotID OR NEW.createdAt IS NOT OLD.createdAt
                BEGIN SELECT RAISE(ABORT, 'JUJU: a take''s audio and identity are immutable'); END;
                CREATE TRIGGER take_never_deleted BEFORE DELETE ON take
                BEGIN SELECT RAISE(ABORT, 'JUJU: takes are never deleted'); END;
                CREATE TRIGGER audio_asset_immutable BEFORE UPDATE ON audioAsset
                BEGIN SELECT RAISE(ABORT, 'JUJU: audio assets are immutable'); END;
                CREATE TRIGGER audio_asset_never_deleted BEFORE DELETE ON audioAsset
                BEGIN SELECT RAISE(ABORT, 'JUJU: audio assets are never deleted'); END;
                CREATE TRIGGER snapshot_immutable BEFORE UPDATE ON takeSettingsSnapshot
                BEGIN SELECT RAISE(ABORT, 'JUJU: take settings snapshots are immutable'); END;
                CREATE TRIGGER settings_revision_immutable BEFORE UPDATE ON jobSettingsRevision
                BEGIN SELECT RAISE(ABORT, 'JUJU: settings revisions are immutable'); END;
                CREATE TRIGGER export_immutable BEFORE UPDATE ON wavExport
                WHEN NEW.id IS NOT OLD.id OR NEW.jobID IS NOT OLD.jobID OR NEW.takeID IS NOT OLD.takeID OR NEW.exportedName IS NOT OLD.exportedName OR NEW.exportedFileChecksum IS NOT OLD.exportedFileChecksum OR NEW.audioDataChecksum IS NOT OLD.audioDataChecksum
                BEGIN SELECT RAISE(ABORT, 'JUJU: export records are immutable'); END;
                CREATE TRIGGER event_append_only_u BEFORE UPDATE ON studioEvent
                BEGIN SELECT RAISE(ABORT, 'JUJU: the event log is append-only'); END;
                CREATE TRIGGER event_append_only_d BEFORE DELETE ON studioEvent
                BEGIN SELECT RAISE(ABORT, 'JUJU: the event log is append-only'); END;
                CREATE TRIGGER take_approval_needs_asset BEFORE UPDATE OF approvalState ON take
                WHEN NEW.approvalState = 'approved' AND (NEW.approvedAssetID IS NULL OR NEW.approvedScriptRevisionID IS NULL)
                BEGIN SELECT RAISE(ABORT, 'JUJU: an approval must name an audio asset and a script revision'); END;
                """)
        }
        return m
    }

    public static func open(at url: URL) throws -> DatabasePool {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.label = "JUJU VO Studio"
        let pool = try DatabasePool(path: url.path, configuration: config)
        try migrator().migrate(pool)
        return pool
    }
}
