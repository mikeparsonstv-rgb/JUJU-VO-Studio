import SwiftUI
import UniformTypeIdentifiers
import VOStudioCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var model = model
        Group {
            if model.library == nil {
                LibrarySetupView()
            } else {
                switch model.screen {
                case .home: HomeView()
                case .studio: StudioView()
                }
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary, lineWidth: 2).padding(6)
                    .overlay(Text("Drop a WAV to open its job").font(.headline).padding(8).background(.regularMaterial, in: Capsule()))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard model.library != nil else { return false }
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in IncomingFiles.shared.receive([url]) } }
                }
            }
            return true
        }
        .sheet(isPresented: $model.showNewJob) { NewJobSheet() }
        .sheet(isPresented: $model.showNewFromSettings) { NewFromSettingsSheet() }
        .sheet(isPresented: $model.showVoices) { VoicesSheet() }
        .sheet(item: $model.recallPrompt) { RecallPromptSheet(prompt: $0) }
        .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
    }
}

struct LibrarySetupView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 16) {
            Text("JUJU VO Studio").font(.largeTitle.weight(.thin))
            Text("Choose a folder for your library. Jobs, takes and the library database are kept there together, so the whole library can be moved or restored as one folder.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 460)
            if let e = model.libraryError { Text(e).foregroundStyle(.red).multilineTextAlignment(.center).frame(maxWidth: 460) }
            Button("Choose Library Folder…") { model.chooseLibraryFolder() }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
        .padding(56).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Home

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""
    @State private var delivered = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("JUJU VO Studio").font(.title2.weight(.semibold))
                Spacer()
                Menu("Library") {
                    Button("Show Library in Finder") { if let r = model.library?.root { NSWorkspace.shared.open(r) } }
                    Button("Choose Another Library…") { model.chooseLibraryFolder() }
                }.menuStyle(.borderlessButton).fixedSize()
            }
            .padding(.horizontal, 44).padding(.top, 24).padding(.bottom, 16)

            if let note = model.repairNote {
                HStack { Image(systemName: "wrench.and.screwdriver"); Text(note); Spacer(); Button("OK") { model.repairNote = nil } }
                    .font(.callout).padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 44).padding(.bottom, 12)
            }

            HStack(spacing: 12) {
                Button { model.showNewJob = true } label: { Label("New Job", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button { model.chooseWAVToOpen() } label: { Label("Open a Delivered WAV…", systemImage: "waveform") }
                    .controlSize(.large)
                Spacer()
                TextField("Filter jobs", text: $filter).textFieldStyle(.roundedBorder).frame(width: 220)
            }
            .padding(.horizontal, 44).padding(.bottom, 12)

            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.secondary)
                TextField("Client only has a file name? Search delivered names", text: $delivered).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search delivered file names")
            }
            .padding(.horizontal, 44).padding(.bottom, 12)

            if delivered.count >= 2 {
                let hits = model.searchDelivered(delivered)
                List(hits) { c in
                    Button { model.land(on: c, notes: []) } label: { CandidateRow(c: c) }.buttonStyle(.plain)
                }
                .overlay { if hits.isEmpty { ContentUnavailableView("No delivered file with that name", systemImage: "magnifyingglass") } }
            } else if model.jobs.isEmpty {
                ContentUnavailableView {
                    Label("No jobs yet", systemImage: "mic")
                } description: {
                    Text("Create your first job, or drop a WAV that JUJU delivered to open its session.")
                } actions: {
                    Button("New Job") { model.showNewJob = true }.buttonStyle(.borderedProminent)
                }
            } else {
                List(model.jobs.filter { filter.isEmpty || $0.job.name.localizedCaseInsensitiveContains(filter) }) { s in
                    Button { model.open(s.job.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.job.name).font(.headline)
                                Text("\(s.takeCount) take\(s.takeCount == 1 ? "" : "s")" + (s.approvedCount > 0 ? " · \(s.approvedCount) approved" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(s.job.lastOpenedAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .contentShape(Rectangle()).padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("Open") { model.open(s.job.id) } }
                }
            }
        }
        .onAppear { model.refreshJobs() }
    }
}

struct CandidateRow: View {
    let c: RecallCandidate
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(c.takeName).font(.body.monospaced())
            Text("\(c.jobName) · \(c.actorName) · \(c.lineLabel) · Take \(c.takeNumber) · \(c.productionDate)").font(.caption).foregroundStyle(.secondary)
            if let e = c.exportSummary { Text(e).font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Sheets

struct NewJobSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var script = ""
    @State private var language = "en-GB"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Job").font(.title3.weight(.semibold))
            TextField("Job name (e.g. Lenor Autumn DE)", text: $name).textFieldStyle(.roundedBorder)
            Picker("Language", selection: $language) {
                ForEach(Languages.all, id: \.tag) { Text($0.name).tag($0.tag) }
            }.fixedSize()
            Text("Script — one line per row; each row becomes Line 01, Line 02…").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $script).font(.body).frame(minHeight: 180).border(.quaternary)
            HStack { Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") { model.createJob(name: name, script: script, languageTag: language); dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 520)
    }
}

struct NewFromSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var copyScript = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New job with these settings").font(.title3.weight(.semibold))
            Text("Settings and cast carry over from “\(model.desk?.job.name ?? "")”. The new job gets its own identity, fresh take numbers and no approvals. The original job and its audio are not changed.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("New job name", text: $name).textFieldStyle(.roundedBorder)
            Toggle("Copy the script too", isOn: $copyScript)
            HStack { Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create Job") { model.newJobFromSettings(name: name, copyScript: copyScript); dismiss() }
                    .keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24).frame(width: 460)
    }
}

struct RecallPromptSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let prompt: AppModel.RecallPrompt
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch prompt {
            case .choose(let cs, let notes, let file):
                Text("Which take is “\(file)”?").font(.title3.weight(.semibold))
                Text("More than one take matches. JUJU won't guess.").foregroundStyle(.secondary)
                ForEach(notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                List(cs) { c in
                    Button { dismiss(); model.land(on: c, notes: notes) } label: { CandidateRow(c: c) }.buttonStyle(.plain)
                }.frame(minHeight: 160)
            case .message(let title, let detail, let url):
                Text(title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if let url, model.desk != nil, model.desk?.bindings.isEmpty == false {
                    Button("Add to “\(model.desk!.job.name)” as an imported take") { dismiss(); model.addTake(.importedWAV(url)) }
                }
            }
            HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width: 520)
    }
}


enum Languages {
    struct L { let tag: String; let name: String }
    /// Locales are distinct choices; dialects are never substituted silently.
    static let all: [L] = [
        L(tag: "en-GB", name: "English (UK)"), L(tag: "en-US", name: "English (US)"),
        L(tag: "de-DE", name: "German (Germany)"), L(tag: "de-AT", name: "German (Austria)"), L(tag: "de-CH", name: "German (Switzerland)"),
        L(tag: "fr-FR", name: "French (France)"), L(tag: "fr-CH", name: "French (Switzerland)"),
        L(tag: "es-ES", name: "Spanish (Spain)"), L(tag: "it-IT", name: "Italian")
    ]
}

struct VoicesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var wav: URL?
    @State private var transcript = ""
    @State private var language = "en-GB"
    @State private var rights = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voices").font(.title3.weight(.semibold))
            if model.voices.isEmpty { Text("No voices yet.").foregroundStyle(.secondary) }
            ForEach(model.voices) { v in
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.voice.displayName).font(.headline)
                    Text("\(v.voice.origin) · \(v.voice.languageTag ?? "") · \(v.references.count) reference recording\(v.references.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(v.voice.rightsNotes).font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            Text("Add a voice from a reference recording").font(.headline)
            TextField("Voice name (as the voice host named it)", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Button(wav == nil ? "Choose Reference WAV…" : wav!.lastPathComponent) {
                    let p = NSOpenPanel(); p.allowedContentTypes = [.wav]
                    if p.runModal() == .OK { wav = p.url }
                }
                Picker("", selection: $language) { ForEach(Languages.all, id: \.tag) { Text($0.name).tag($0.tag) } }.fixedSize()
            }
            TextField("Exact transcript of the reference (improves cloning)", text: $transcript, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder)
            TextField("Rights / permission notes", text: $rights).textFieldStyle(.roundedBorder)
            HStack { Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Voice") { if let wav { model.addVoice(name: name, wav: wav, transcript: transcript, language: language, rights: rights); name = ""; self.wav = nil; transcript = "" } }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || wav == nil)
            }
        }
        .padding(24).frame(width: 520)
    }
}
