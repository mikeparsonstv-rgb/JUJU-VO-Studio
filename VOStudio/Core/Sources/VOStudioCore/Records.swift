import Foundation
import GRDB

// Canonical JUJU-owned records (Build 01 brief §3, Stage 1 subset). Stable UUIDs, never display text, are keys.
// Column names equal property names. UUIDs are stored as lowercase TEXT via `UUIDText`.

public struct Client: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID; public var displayName: String; public var aliasesJSON: String; public var notes: String
}
public struct Brand: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID; public var clientID: UUID?; public var displayName: String; public var aliasesJSON: String
}
public struct Market: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID; public var countryCode: String; public var languageTag: String; public var dialectTag: String?; public var notes: String
}

public struct Job: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID
    public var name: String
    public var clientID: UUID?
    public var brandID: UUID?
    public var marketID: UUID?
    public var createdAt: Date
    public var lastOpenedAt: Date
    public var lastActivityAt: Date
    public var currentScriptRevisionID: UUID?
    public var sourceJobID: UUID?
    public var status: String                 // "active" | "archived"
    public var settingsSchemaVersion: Int
    public var currentSettingsRevisionID: UUID?
}

public struct ScriptRevision: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID; public var jobID: UUID; public var rawText: String; public var createdAt: Date
}

/// A logical script line. `stableLineNumber` is the director's "line three", not a UI wrap.
public struct ScriptSegment: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID; public var revisionID: UUID; public var stableLineNumber: Int
    public var text: String; public var order: Int; public var character: String?
}

public struct VoiceMaster: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID
    public var displayName: String
    /// hostCloned | generated | licensed | placeholder. Stage 1 creates placeholders only.
    public var origin: String
    public var languageTag: String?
    public var rightsNotes: String
    public var createdAt: Date
    public var isPlaceholder: Bool { origin == "placeholder" }
}

public struct RendererProfile: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID; public var voiceMasterID: UUID; public var engineID: String; public var backendVoiceID: String?
    public var modelVersion: String?; public var conditioningJSON: String?; public var state: String; public var createdAt: Date
}

public struct JobActorBinding: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID
    public var jobID: UUID
    public var voiceMasterID: UUID
    public var selectedRendererProfileID: UUID?
    public var state: String                  // audition | approved
    /// Display name at binding time and its filename token (unique within the job; fixed once set).
    public var actorDisplayName: String
    public var fileToken: String
    public var notes: String
    public var createdAt: Date
}

public struct AudioAsset: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID
    public var kind: String                   // take
    public var relativePath: String           // relative to the library root
    public var fileChecksum: String           // SHA-256 of the whole file
    public var dataChecksum: String           // SHA-256 of the data chunk (audio bytes only)
    public var codec: String                  // pcm | float
    public var sampleRate: Int
    public var bitsPerSample: Int
    public var channels: Int
    public var duration: Double
    public var captureSource: String          // importedWAV | mockFixture | render
    public var createdAt: Date
}

public struct Take: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID
    public var jobID: UUID
    public var segmentID: UUID?               // nil = full read
    public var lineKey: Int                   // stableLineNumber, 0 = full read
    public var perLineTakeNumber: Int
    public var actorBindingID: UUID
    public var voiceMasterID: UUID
    public var actorDisplayNameSnapshot: String
    public var rendererSnapshotJSON: String
    public var scriptRevisionID: UUID
    public var segmentTextSnapshot: String
    public var outputAssetID: UUID
    public var provenance: String             // importedWAV | mockFixture | render
    public var status: String                 // accepted
    public var approvalState: String          // none | approved
    public var approvedAssetID: UUID?
    public var approvedScriptRevisionID: UUID?
    public var approvedAt: Date?
    public var canonicalBasename: String      // e.g. JobA-Jane-2026-10-28-Line03-Take04 (no extension)
    public var productionDate: String         // local yyyy-MM-dd at creation
    public var takeSettingsSnapshotID: UUID
    public var createdAt: Date
    public var lineLabel: String { lineKey == 0 ? "Full read" : "Line \(String(format: "%02d", lineKey))" }
    public var isApproved: Bool { approvalState == "approved" }
}

public struct JobSettingsRevision: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID; public var jobID: UUID; public var schemaVersion: Int; public var canonicalSettingsJSON: String
    public var createdAt: Date; public var sourceJobSettingsRevisionID: UUID?; public var authoredBy: String
}

/// Resolved values actually used for a take. Evidence for reproduction, not a guarantee of it.
public struct TakeSettingsSnapshot: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID
    public var takeID: UUID
    public var jobSettingsRevisionID: UUID
    public var resolvedSettingsJSON: String
    public var scriptRevisionID: UUID
    public var voiceMasterID: UUID
    public var rendererProfileID: UUID?
    public var engineBuild: String?
    public var modelRevision: String?
    public var conditioningJSON: String?
    public var randomSeed: Int64?
    public var outputFormatJSON: String
    public var appBuild: String
    public var createdAt: Date
}

public struct WAVExport: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID
    public var jobID: UUID
    public var takeID: UUID
    public var sourceAudioAssetID: UUID
    public var exportedName: String           // file name actually written (with .wav)
    public var lastKnownPath: String          // convenience only — recall never depends on it
    public var exportedFileChecksum: String
    public var audioDataChecksum: String
    public var exportedAt: Date
    public var takeSettingsSnapshotID: UUID
    public var metadataSchemaVersion: Int
    public var byteFormat: String
    public var sampleRate: Int
    public var bitDepth: Int
    public var channelCount: Int
}

public struct WAVRecallIndexEntry: Codable, Sendable, Equatable, StudioRecord {
    public var id: UUID
    public var jobID: UUID
    public var takeID: UUID
    public var wavExportID: UUID
    public var canonicalExportFilename: String
    public var basenameKey: String            // normalised lookup key (see CanonicalNaming.lookupKey)
    public var candidateAudioChecksum: String
    public var metadataVersion: Int
}

public struct EngineerSession: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID; public var jobID: UUID; public var mode: String; public var provider: String
    public var startedAt: Date; public var lastStatus: String
}

/// Director intent. `source` carries the two direction routes from day one (STAGE0_AUDIT §1).
public struct DirectionEvent: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID
    public var jobID: UUID
    public var sessionID: UUID?
    public var targetSegmentIDsJSON: String
    public var transcript: String
    public var intent: String?
    public var source: String                 // guideDerived | conversationDerived | manualText
    public var rawAudioAssetID: UUID?
    public var proposedAction: String?
    public var confirmedAction: String?
    public var createdAt: Date
}

/// Append-only log of critical actions (create, import, approve, export, new-from-settings). Never updated or deleted.
public struct StudioEvent: Codable, Sendable, Equatable, StudioRecord, Identifiable {
    public var id: UUID; public var jobID: UUID?; public var takeID: UUID?; public var kind: String
    public var payloadJSON: String; public var createdAt: Date
}

