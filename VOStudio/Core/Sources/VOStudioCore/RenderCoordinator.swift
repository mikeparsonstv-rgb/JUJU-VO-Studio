import Foundation
import GRDB

public struct RenderUpdate: Sendable, Equatable {
    public let run: RenderRun
    public let take: Take?
}

/// Owns the render pipeline: persist the run (queued) → engine render → independent validation →
/// atomic take save → run succeeded. Every failure is recorded honestly; nothing is reported ready early.
public actor RenderCoordinator {
    public let library: StudioLibrary
    private var engines: [String: any ActorEngine] = [:]
    private var listeners: [UUID: AsyncStream<RenderUpdate>.Continuation] = [:]
    private var tail: Task<Void, Never>?

    public init(library: StudioLibrary) { self.library = library }

    public func register(_ engine: any ActorEngine) { engines[engine.descriptor.id] = engine }
    public func engine(_ id: String) -> (any ActorEngine)? { engines[id] }
    public var engineIDs: [String] { Array(engines.keys).sorted() }

    public func updates() -> AsyncStream<RenderUpdate> {
        let id = UUID()
        return AsyncStream { c in
            listeners[id] = c
            c.onTermination = { _ in Task { await self.removeListener(id) } }
        }
    }
    private func removeListener(_ id: UUID) { listeners[id] = nil }
    private func emit(_ u: RenderUpdate) { for c in listeners.values { c.yield(u) } }

    /// Persists a queued run and returns it at once; rendering happens in order behind it.
    @discardableResult
    public func enqueue(jobID: UUID, actorBindingID: UUID, segmentID: UUID?, engineID: String,
                        direction: PerformanceDirection = .init(), directionEventID: UUID? = nil,
                        referenceID: UUID? = nil) throws -> RenderRun {
        guard let engine = engines[engineID] else { throw LibraryError.audioUnreadable("engine \(engineID) is not available") }
        let (_, voice, refs) = try library.voice(for: actorBindingID)
        guard voice.origin != "placeholder" else {
            throw LibraryError.audioUnreadable("\(voice.displayName) is a placeholder with no voice — cast a real voice to render")
        }
        guard let ref = refs.first(where: { $0.id == referenceID }) ?? refs.first else {
            throw LibraryError.audioUnreadable("\(voice.displayName) has no reference recording")
        }
        let now = Date()
        let request: [String: String] = ["engine": engine.descriptor.id, "voice": voice.displayName,
                                         "referenceID": ref.id.uuidString.lowercased(),
                                         "direction": JSON.encode(direction)]
        let run = RenderRun(id: UUID(), jobID: jobID, actorBindingID: actorBindingID, segmentID: segmentID, engineID: engineID,
                            state: "queued", requestJSON: JSON.encode(request), resultJSON: nil, error: nil, takeID: nil,
                            directionEventID: directionEventID, createdAt: now, startedAt: nil, finishedAt: nil)
        try library.db.write { try run.insert($0) }
        emit(RenderUpdate(run: run, take: nil))
        let previous = tail
        tail = Task {
            await previous?.value
            await self.perform(run, engine: engine, reference: ref, voice: voice, direction: direction)
        }
        return run
    }

    /// Waits until everything queued so far has finished (tests, shutdown).
    public func drain() async { await tail?.value }

    private func perform(_ queued: RenderRun, engine: any ActorEngine, reference: VoiceReference, voice: VoiceMaster,
                         direction: PerformanceDirection) async {
        var run = queued
        let runID = queued.id
        let started = Date()
        do {
            try await library.db.write { db in
                try db.execute(sql: "UPDATE renderRun SET state='rendering', startedAt=? WHERE id=? AND state='queued'", arguments: [started, runID])
            }
            run.state = "rendering"; run.startedAt = started
            emit(RenderUpdate(run: run, take: nil))

            let desk = try library.desk(run.jobID)
            let text: String
            if let seg = desk.segments.first(where: { $0.id == run.segmentID }) { text = seg.text }
            else { text = desk.segments.map(\.text).joined(separator: "\n") }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LibraryError.segmentNotInJob }
            guard FileManager.default.fileExists(atPath: reference.localPath) else {
                throw LibraryError.audioUnreadable("\(voice.displayName)'s reference recording is missing: \(reference.localPath)")
            }
            let language = desk.settings.languageTag ?? reference.languageTag
            let rendersDir = library.root.appendingPathComponent("Library/\(run.jobID.uuidString.lowercased())/renders")
            try FileManager.default.createDirectory(at: rendersDir, withIntermediateDirectories: true)
            let out = rendersDir.appendingPathComponent("\(run.id.uuidString.lowercased()).wav")
            let seed = UInt64.random(in: 1...UInt64(Int32.max))
            let request = ActorRenderRequest(runID: run.id, text: text, languageTag: language, referencePath: reference.localPath,
                                             referenceTranscript: reference.transcript,
                                             referenceAssetID: "voice-\(voice.id.uuidString.lowercased())-ref-\(reference.id.uuidString.lowercased())",
                                             direction: direction, seed: seed, outputURL: out)
            let output = try await engine.render(request)
            let post = try DigitalSilence.trimTrailingZeros(at: out)
            let profileID = try library.ensureRendererProfile(voiceMasterID: voice.id, engine: engine.descriptor, reference: reference)
            let provenance = RenderProvenance(runID: run.id, engine: engine.descriptor, rendererProfileID: profileID, referenceID: reference.id,
                                              referenceLabel: reference.label, referenceSHA256: reference.sha256,
                                              referenceTranscriptPresent: reference.transcript != nil, languageTag: language, seed: seed,
                                              scriptText: text, output: output, direction: direction, directionEventID: run.directionEventID,
                                              postProcessing: post)
            let take = try library.addTake(jobID: run.jobID, actorBindingID: run.actorBindingID, segmentID: run.segmentID,
                                           audio: .rendered(out, provenance))
            try? FileManager.default.removeItem(at: out)
            run.state = "succeeded"; run.takeID = take.id; run.finishedAt = Date(); run.resultJSON = JSON.encode(output)
            emit(RenderUpdate(run: run, take: take))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let finished = Date()
            try? await library.db.write { db in
                try db.execute(sql: "UPDATE renderRun SET state='failed', error=?, finishedAt=? WHERE id=? AND state IN ('queued','rendering')",
                               arguments: [message, finished, runID])
            }
            let rendersDir = library.root.appendingPathComponent("Library/\(run.jobID.uuidString.lowercased())/renders")
            try? FileManager.default.removeItem(at: rendersDir.appendingPathComponent("\(run.id.uuidString.lowercased()).wav"))
            run.state = "failed"; run.error = message; run.finishedAt = finished
            emit(RenderUpdate(run: run, take: nil))
        }
    }
}

extension StudioLibrary {
    /// One profile per voice × engine × reference; reused across takes, captured on each take snapshot.
    func ensureRendererProfile(voiceMasterID: UUID, engine: ActorEngineDescriptor, reference: VoiceReference) throws -> UUID {
        try db.write { db in
            let backend = "ref-\(reference.id.uuidString.lowercased())"
            if let existing = try RendererProfile.filter(Column("voiceMasterID") == voiceMasterID && Column("engineID") == engine.id
                                                         && Column("backendVoiceID") == backend).fetchOne(db) { return existing.id }
            let p = RendererProfile(id: UUID(), voiceMasterID: voiceMasterID, engineID: engine.id, backendVoiceID: backend,
                                    modelVersion: engine.modelRevision,
                                    conditioningJSON: JSON.encode(["referenceSHA256": reference.sha256, "transcriptPresent": String(reference.transcript != nil)]),
                                    state: "ready", createdAt: Date())
            try p.insert(db)
            return p.id
        }
    }

    public func renderRuns(jobID: UUID, limit: Int = 50) throws -> [RenderRun] {
        try db.read { try RenderRun.filter(Column("jobID") == jobID).order(Column("createdAt").desc).limit(limit).fetchAll($0) }
    }

    /// Director intent, verbatim, before any render it drives.
    @discardableResult
    public func recordDirection(jobID: UUID, segmentIDs: [UUID], transcript: String, source: String,
                                intent: PerformanceDirection?, proposedAction: String?, confirmedAction: String?) throws -> DirectionEvent {
        let e = DirectionEvent(id: UUID(), jobID: jobID, sessionID: nil, targetSegmentIDsJSON: JSON.encode(segmentIDs.map { $0.uuidString.lowercased() }),
                               transcript: transcript, intent: intent.map { JSON.encode($0) }, source: source, rawAudioAssetID: nil,
                               proposedAction: proposedAction, confirmedAction: confirmedAction, createdAt: clock())
        try db.write { try e.insert($0) }
        return e
    }

    public func directions(jobID: UUID, limit: Int = 100) throws -> [DirectionEvent] {
        try db.read { try DirectionEvent.filter(Column("jobID") == jobID).order(Column("createdAt").desc).limit(limit).fetchAll($0) }
    }

    public func snapshot(for take: Take) throws -> TakeSettingsSnapshot? {
        try db.read { try TakeSettingsSnapshot.fetchOne($0, key: take.takeSettingsSnapshotID) }
    }
}
