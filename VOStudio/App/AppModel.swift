import SwiftUI
import AppKit
import AVFoundation
import VOStudioCore

/// The session's working state. Stage 1: no Engineer, no renderer — the desk, the takes and WAV recall.
@MainActor @Observable
final class AppModel {
    enum Screen: Equatable { case home, studio(UUID) }

    /// A dropped WAV that resolved to a take: the original read goes on the desk with this welcome.
    struct Welcome: Equatable { let candidate: RecallCandidate; let text: String; let notes: [String] }

    enum RecallPrompt: Identifiable {
        case choose([RecallCandidate], notes: [String], fileName: String)
        case message(title: String, detail: String, fileURL: URL?)
        var id: String {
            switch self {
            case .choose(let c, _, let f): "choose-\(f)-\(c.count)"
            case .message(let t, let d, _): "msg-\(t)-\(d.hashValue)"
            }
        }
    }

    private(set) var library: StudioLibrary?
    var libraryError: String?
    var screen: Screen = .home
    var jobs: [JobSummary] = []
    var desk: JobDesk?
    var selectedSegmentID: UUID?                   // nil = full read
    var selectedBindingID: UUID?
    var selectedTakeID: UUID?
    var welcome: Welcome?
    var recallPrompt: RecallPrompt?
    var errorMessage: String?
    var showNewJob = false
    var showNewFromSettings = false
    var repairNote: String?
    var peaks: [Float] = []
    // Stage 2: voices and rendering
    var voices: [VoiceSummary] = []
    var showVoices = false
    private(set) var renderer: RenderCoordinator?
    private var qwen: QwenBenchActorEngine?
    var engineStatus = "Voice engine not started"
    var engineReady = false
    var runs: [UUID: RenderRun] = [:]
    var autoPlayNewTakes = true
    var latestRenderNote: String?
    // Stage 3: the Engineer
    private(set) var engineer: Engineer?
    let engineerVoice = SystemEngineerVoice()
    let mic = DirectorMic()
    let llm = EngineerLLMServer()
    var micPartial = ""
    var llmStatus = "off"
    var engineerConnected: Bool { engineer?.isConnected == true }
    var isPlaying = false
    private var player: AVAudioPlayer?
    private var playbackStop: Task<Void, Never>?

    private static let rootBookmarkKey = "libraryRootBookmark"
    private var appBuild: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "0") (\(i?["CFBundleVersion"] as? String ?? "0"))"
    }

    // MARK: Library

    func start() {
        guard library == nil else { return }
        if let data = UserDefaults.standard.data(forKey: Self.rootBookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                openLibrary(at: url)
                if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: Self.rootBookmarkKey) }
                return
            }
            libraryError = "The saved library folder can't be found. Choose it again, or choose a new folder."
        }
    }

    func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose the JUJU VO Studio library folder"
        panel.message = "Jobs, takes and the library database live here. Choose an existing library to reopen it."
        panel.prompt = "Use This Folder"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openLibrary(at: url)
        if library != nil, let data = try? url.bookmarkData() { UserDefaults.standard.set(data, forKey: Self.rootBookmarkKey) }
    }

    private func openLibrary(at url: URL) {
        do {
            let lib = try StudioLibrary(root: url, appBuild: appBuild)
            library = lib; libraryError = nil
            let report = try lib.repairAfterLaunch()
            if !report.removedTempFiles.isEmpty || !report.unreferencedTakeFiles.isEmpty {
                repairNote = "Tidied \(report.removedTempFiles.count) unfinished write(s) from a previous session."
                    + (report.unreferencedTakeFiles.isEmpty ? "" : " \(report.unreferencedTakeFiles.count) take file(s) aren't in the database and were left untouched.")
            }
            screen = .home; refreshJobs(); refreshVoices()
            if report.interruptedRuns > 0 { repairNote = (repairNote ?? "") + " \(report.interruptedRuns) render(s) were interrupted when the app last closed." }
            startEngines(lib)
            IncomingFiles.shared.attach { [weak self] urls in self?.handleIncoming(urls) }
        } catch {
            libraryError = "Couldn't open the library at \(url.path): \(error.localizedDescription)"
        }
    }

    func refreshJobs() { jobs = (try? library?.recentJobs()) ?? [] }
    func refreshVoices() { voices = (try? library?.voices()) ?? [] }

    // MARK: Engines (Stage 2)

    // MARK: Engineer (Stage 3)

    func connectEngineer() async {
        guard library != nil else { return }
        if engineer == nil { engineer = Engineer(studio: self, voice: engineerVoice) }
        guard let e = engineer, !e.isConnected else { return }
        mic.onPartial = { [weak self] in self?.micPartial = $0 }
        mic.onUtterance = { [weak self] text, ended in Task { @MainActor in await self?.engineer?.hear(text, endedAt: ended) } }
        mic.shouldGate = { [weak self] in
            guard let self else { return true }
            return self.engineerVoice.isSpeaking || self.isPlaying || self.engineer?.state == .working
        }
        let greeting: String
        if let w = welcome { greeting = w.text }
        else if let d = desk {
            let actor = d.bindings.first { $0.id == selectedBindingID }?.actorDisplayName
            greeting = "Hi, I'm here. We're on \(d.job.name), \(spokenLine)\(actor.map { ", with \($0)" } ?? "")."
        } else { greeting = "Hi, I'm here. Open a job, or tell me which one." }
        llmStatus = "starting…"
        Task {
            do {
                try await llm.ensureRunning()
                let provider = OpenAICompatibleProvider(name: llm.modelName, baseURL: llm.baseURL, timeout: 25)
                llmStatus = "warming up…"
                _ = try? await provider.interpret("hello", context: engineerContext, history: [])
                e.provider = provider
                llmStatus = "ready"
            } catch {
                llmStatus = "unavailable — \(error.localizedDescription)"
            }
        }
        await e.connect(greeting: greeting)
        Task { await mic.start() }     // permission prompts must never hold up the Engineer (typed direction still works)
    }

    func disconnectEngineer() {
        engineer?.disconnect()
        mic.stop()
        micPartial = ""
    }

    func typedDirection(_ text: String) {
        Task { await engineer?.hear(text) }
    }

    private func startEngines(_ lib: StudioLibrary) {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.llm.stop(); self?.mic.stop() }
        }
        let rc = RenderCoordinator(library: lib)
        renderer = rc
        let engine = QwenBenchActorEngine(benchRoot: QwenBenchActorEngine.defaultBenchRoot)
        qwen = engine
        Task {
            await rc.register(engine)
            let stream = await rc.updates()
            Task { @MainActor [weak self] in for await u in stream { self?.renderUpdate(u) } }
            guard engine.isAvailable else { engineStatus = "Qwen not found — Renderer Bench folder missing"; return }
            engineStatus = "Loading Qwen 0.6B…"
            do { try await engine.warmUp(); engineReady = true; engineStatus = "Qwen 0.6B ready" }
            catch { engineStatus = "Qwen failed to load: \(error.localizedDescription)" }
        }
    }

    func shutdownEngines() async { await qwen?.shutdown() }

    var canRender: Bool {
        guard let d = desk, let b = d.bindings.first(where: { $0.id == selectedBindingID }) else { return false }
        return voices.contains { $0.voice.id == b.voiceMasterID } && qwen?.isAvailable == true
    }

    var selectedActorIsPlaceholder: Bool {
        guard let d = desk, let b = d.bindings.first(where: { $0.id == selectedBindingID }) else { return false }
        return !voices.contains { $0.voice.id == b.voiceMasterID }
    }

    /// Queues a render of the selected line (or full read) with the selected actor; returns the queued run.
    @discardableResult
    func render(_ direction: PerformanceDirection = .init(), source: String = "manualText", segmentID: UUID?? = nil,
                bindingID: UUID? = nil) async -> RenderRun? {
        guard let library, let rc = renderer, let d = desk else { return nil }
        guard let binding = bindingID ?? selectedBindingID else { errorMessage = "Cast a voice first."; return nil }
        let seg = segmentID ?? selectedSegmentID
        var eventID: UUID?
        if !direction.isEmpty {
            eventID = try? library.recordDirection(jobID: d.job.id, segmentIDs: seg.map { [$0] } ?? [],
                                                   transcript: direction.note.isEmpty ? direction.variation.rawValue : direction.note,
                                                   source: source, intent: direction, proposedAction: "render", confirmedAction: "render").id
        }
        do {
            let q = try await rc.enqueue(jobID: d.job.id, actorBindingID: binding, segmentID: seg, engineID: "qwen3-bench",
                                         direction: direction, directionEventID: eventID)
            runs[q.id] = q
            return q
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    private func renderUpdate(_ u: RenderUpdate) {
        runs[u.run.id] = u.run
        if u.run.state == "failed" { latestRenderNote = "Render failed: \(u.run.error ?? "unknown error")" }
        guard u.run.jobID == desk?.job.id else { return }
        if u.run.state == "succeeded", let take = u.take {
            reloadDesk()
            selectedSegmentID = take.segmentID; selectedBindingID = take.actorBindingID
            select(take: take.id)
            latestRenderNote = nil
            Task {
                let announced = await engineer?.renderFinished(runID: u.run.id, takeID: take.id, error: nil) ?? false
                if !announced && autoPlayNewTakes { try? await Task.sleep(for: .milliseconds(250)); self.play() }
            }
        } else if u.run.state == "failed" {
            Task { await engineer?.renderFinished(runID: u.run.id, takeID: nil, error: u.run.error) }
        }
        onRenderUpdate?(u)
    }

    /// Hook for the Engineer (Stage 3).
    var onRenderUpdate: ((RenderUpdate) -> Void)?

    var activeRunsForDesk: [RenderRun] {
        runs.values.filter { $0.jobID == desk?.job.id && !$0.isFinished }.sorted { $0.createdAt < $1.createdAt }
    }

    func castVoice(_ id: UUID) {
        guard let library, let jobID = desk?.job.id else { return }
        run { let b = try library.cast(voiceMasterID: id, into: jobID); self.reloadDesk(); self.selectedBindingID = b.id }
    }

    func addVoice(name: String, wav: URL, transcript: String, language: String, rights: String) {
        guard let library else { return }
        run { _ = try library.addVoice(displayName: name, origin: "hostCloned", languageTag: language, rightsNotes: rights,
                                       referenceWAV: wav, transcript: transcript); self.refreshVoices() }
    }

    // MARK: Jobs

    func createJob(name: String, script: String, languageTag: String = "en-GB") {
        guard let library else { return }
        run { let job = try library.createJob(name: name, script: script, languageTag: languageTag); self.open(job.id) }
    }

    func open(_ jobID: UUID, selecting takeID: UUID? = nil) {
        guard let library else { return }
        run {
            try library.markOpened(jobID)
            let d = try library.desk(jobID)
            self.stop()
            self.desk = d
            self.screen = .studio(jobID)
            self.selectedBindingID = d.bindings.first?.id
            if let takeID, let t = d.takes.first(where: { $0.id == takeID }) {
                self.selectedSegmentID = t.segmentID; self.selectedBindingID = t.actorBindingID; self.select(take: t.id)
            } else {
                self.selectedSegmentID = d.segments.first?.id
                self.select(take: d.takes.last?.id)
            }
        }
    }

    func goHome() { stop(); welcome = nil; desk = nil; screen = .home; refreshJobs() }

    func reloadDesk() {
        guard let library, let id = desk?.job.id else { return }
        run { self.desk = try library.desk(id) }
    }

    // MARK: Cast and takes

    func addActor(named name: String) {
        guard let library, let jobID = desk?.job.id else { return }
        run { let b = try library.addPlaceholderActor(jobID: jobID, displayName: name); self.reloadDesk(); self.selectedBindingID = b.id }
    }

    func addTake(_ source: TakeAudioSource) {
        guard let library, let d = desk else { return }
        guard let binding = selectedBindingID ?? d.bindings.first?.id else {
            errorMessage = "Cast an actor first (Stage 1 uses a placeholder voice)."; return
        }
        run {
            let take = try library.addTake(jobID: d.job.id, actorBindingID: binding, segmentID: self.selectedSegmentID, audio: source)
            self.reloadDesk(); self.select(take: take.id)
        }
    }

    func addTakeFromWAV() {
        let panel = NSOpenPanel()
        panel.title = "Add a take from a WAV"
        panel.message = "The file is copied into the library unchanged and labelled as an imported WAV."
        panel.allowedContentTypes = [.wav]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addTake(.importedWAV(url))
    }

    func toggleApproval() {
        guard let library, let t = selectedTake else { return }
        run { try library.setApproval(takeID: t.id, approved: !t.isApproved); self.reloadDesk() }
    }

    func exportSelected(format: DeliveryFormat = .broadcast48k24) {
        guard let library, let t = selectedTake, let d = desk else { return }
        let panel = NSOpenPanel()
        panel.title = "Export \(t.canonicalBasename).wav — \(format.label)"
        panel.prompt = "Export Here"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        let defaultDir = library.root.appendingPathComponent("Exports").appendingPathComponent(CanonicalNaming.token(d.job.name, fallback: "Job"))
        try? FileManager.default.createDirectory(at: defaultDir, withIntermediateDirectories: true)
        panel.directoryURL = defaultDir
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        run {
            let e = try library.exportTake(t.id, to: folder, format: format)
            self.reloadDesk()
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: e.lastKnownPath)])
        }
    }

    var selectedTake: Take? { desk?.takes.first { $0.id == selectedTakeID } }

    func select(take id: UUID?) {
        stop()
        selectedTakeID = id
        peaks = []
        guard let library, let t = selectedTake, let a = desk?.assets[t.outputAssetID], desk?.missingAudio.contains(t.id) == false else { return }
        let url = library.url(for: a)
        Task.detached(priority: .userInitiated) {
            let p = WaveformPeaks.compute(fileAt: url, buckets: 480)
            await MainActor.run { if self.selectedTakeID == id { self.peaks = p } }
        }
    }

    // MARK: Playback (one playback authority)

    var playbackDuration: Double { player?.duration ?? 0 }
    var playbackStartedAt: Date?

    func togglePlay() { isPlaying ? stop() : play() }

    func play() {
        guard let library, let t = selectedTake, let a = desk?.assets[t.outputAssetID] else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: library.url(for: a))
            p.prepareToPlay(); p.play()
            player = p; isPlaying = true; playbackStartedAt = Date()
            let duration = p.duration
            playbackStop = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration + 0.05))
                if !Task.isCancelled { self?.stop() }
            }
        } catch { errorMessage = "Can't play this take: \(error.localizedDescription)" }
    }

    func stop() {
        playbackStop?.cancel(); playbackStop = nil
        player?.stop(); player = nil; isPlaying = false; playbackStartedAt = nil
    }

    // MARK: WAV recall (brief §7A)

    func chooseWAVToOpen() {
        let panel = NSOpenPanel()
        panel.title = "Open a delivered WAV"
        panel.message = "JUJU finds the job and take that made it. Nothing is changed."
        panel.allowedContentTypes = [.wav]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        handleIncoming([url])
    }

    func handleIncoming(_ urls: [URL]) {
        guard let library, let url = urls.first(where: { $0.isFileURL }) else { return }
        NSApp.activate()
        switch library.resolve(fileAt: url) {
        case .found(let c, _, let notes):
            land(on: c, notes: notes)
        case .chooseOne(let cs, let notes):
            recallPrompt = .choose(cs, notes: notes, fileName: url.lastPathComponent)
        case .jobNotInLibrary(let jobID, let takeID):
            recallPrompt = .message(title: "This file came from a JUJU job, but the source project isn't available here.",
                                    detail: "Job \(jobID.uuidString.lowercased())\nTake \(takeID.uuidString.lowercased())\n\nIf the job lives in another JUJU library (another Mac, an archive), open that library folder from Home › Library. The WAV alone is not a job archive.",
                                    fileURL: url)
        case .takeNotInJob(_, let takeID, let jobName):
            recallPrompt = .message(title: "“\(jobName)” is here, but not the take this file came from.",
                                    detail: "Take \(takeID.uuidString.lowercased())\n\nThe library may be an older copy of the job.", fileURL: url)
        case .noMatch(let notes):
            recallPrompt = .message(title: "No JUJU job is known for “\(url.lastPathComponent)”.",
                                    detail: (notes + ["It carries no JUJU identifiers, and no export, take name or identical audio matches it. You can add it to an open job as an imported take, or search delivered file names on Home."]).joined(separator: "\n\n"),
                                    fileURL: url)
        case .unreadable(let why):
            recallPrompt = .message(title: "“\(url.lastPathComponent)” can't be read as a WAV.", detail: why, fileURL: nil)
        }
    }

    func land(on c: RecallCandidate, notes: [String]) {
        open(c.jobID, selecting: c.takeID)
        welcome = Welcome(candidate: c, text: Self.welcomeText(c), notes: notes)
        if engineerConnected, let w = welcome { Task { await engineer?.say(w.text) } }
    }

    static func welcomeText(_ c: RecallCandidate) -> String {
        let line = c.lineLabel == "Full read" ? "full read" : "line \(spoken(Int(c.lineLabel.dropFirst(5)) ?? 0))"
        return "Welcome back. I've got \(c.actorName)'s \(line), take \(spoken(c.takeNumber)), from \(c.jobName). Are we making changes to this today, or doing something new with the same settings?"
    }

    nonisolated static func spoken(_ n: Int) -> String {
        let w = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
                 "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"]
        return n >= 0 && n < w.count ? w[n] : String(n)
    }

    /// "Make changes today": stay on the original job; the next take on this line becomes a new take.
    func continueThisJob() { welcome = nil }

    /// "New job with these settings": new identity, settings and cast inherited, source untouched.
    func newJobFromSettings(name: String, copyScript: Bool) {
        guard let library, let source = desk?.job.id else { return }
        run { let j = try library.newJob(fromSettingsOf: source, name: name, copyScript: copyScript); self.welcome = nil; self.open(j.id) }
    }

    func searchDelivered(_ q: String) -> [RecallCandidate] { (try? library?.searchDeliveredNames(q)) ?? [] }

    // MARK: Errors

    private func run(_ body: () throws -> Void) {
        do { try body() } catch { errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}
