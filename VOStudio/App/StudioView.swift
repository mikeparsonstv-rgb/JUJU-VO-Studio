import SwiftUI
import VOStudioCore

struct StudioView: View {
    @Environment(AppModel.self) private var model
    @State private var newActor = ""

    var body: some View {
        if let d = model.desk {
            VStack(spacing: 0) {
                header(d)
                if let w = model.welcome { WelcomeBanner(welcome: w) }
                HStack(alignment: .top, spacing: 0) {
                    scriptColumn(d).frame(width: 300)
                    Divider()
                    centre(d).frame(maxWidth: .infinity)
                    Divider()
                    VStack(spacing: 0) {
                        castColumn(d)
                        Divider()
                        EngineerPanel().frame(minHeight: 300)
                    }.frame(width: 300)
                }
            }
        }
    }

    private func header(_ d: JobDesk) -> some View {
        HStack(spacing: 12) {
            Button { model.goHome() } label: { Label("Jobs", systemImage: "chevron.left") }
                .keyboardShortcut("[", modifiers: .command)
            Text(d.job.name).font(.title3.weight(.semibold)).lineLimit(1)
            if let src = d.job.sourceJobID, src != d.job.id { Text("from earlier job").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Label(model.engineStatus, systemImage: model.engineReady ? "waveform.circle.fill" : "waveform.circle")
                .font(.caption).foregroundStyle(.secondary).accessibilityLabel("Voice engine: \(model.engineStatus)")
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    // MARK: Script

    private func scriptColumn(_ d: JobDesk) -> some View {
        List(selection: Binding(get: { model.selectedSegmentID ?? Self.fullReadID }, set: { model.selectedSegmentID = $0 == Self.fullReadID ? nil : $0 })) {
            Section("Script") {
                Text("Full read").tag(Self.fullReadID)
                ForEach(d.segments) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%02d", s.stableLineNumber)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text(s.text).lineLimit(3)
                    }.tag(s.id)
                }
            }
        }
    }
    private static let fullReadID = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))

    // MARK: Centre: player, take, takes

    private func centre(_ d: JobDesk) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let t = model.selectedTake {
                takeHeader(t, d)
                WaveformView(peaks: model.peaks, missing: d.missingAudio.contains(t.id))
                    .frame(height: 96)
                HStack(spacing: 10) {
                    Button { model.togglePlay() } label: { Label(model.isPlaying ? "Stop" : "Play", systemImage: model.isPlaying ? "stop.fill" : "play.fill") }
                        .keyboardShortcut(.space, modifiers: []).disabled(d.missingAudio.contains(t.id))
                    Button { model.toggleApproval() } label: { Label(t.isApproved ? "Approved" : "Approve", systemImage: t.isApproved ? "checkmark.seal.fill" : "checkmark.seal") }
                        .keyboardShortcut("a", modifiers: .command)
                    Button { model.exportSelected() } label: { Label("Export 48k/24…", systemImage: "square.and.arrow.up") }
                        .keyboardShortcut("e", modifiers: .command).disabled(d.missingAudio.contains(t.id))
                    Spacer()
                }
                if let exports = d.exportsByTake[t.id], !exports.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delivered").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(exports) { e in
                            Text("\(e.exportedName) · \(e.sampleRate) Hz · \(e.bitDepth)-bit\(e.conversionNote != nil ? " (converted)" : "") · \(e.exportedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            } else {
                ContentUnavailableView("No take selected", systemImage: "waveform", description: Text(d.bindings.isEmpty ? "Cast an actor, then add a take." : "Add a take for the selected line."))
                    .frame(height: 220)
            }
            Divider()
            RenderBar(desk: d)
            HStack {
                Text("Takes").font(.headline)
                Spacer()
                Menu {
                    Button("Export Native WAV (as rendered)…") { model.exportSelected(format: .native) }.disabled(model.selectedTake == nil)
                    Button("Add Take from WAV…") { model.addTakeFromWAV() }
                    Button("Add Mock Tone (test)") { model.addTake(.mockTone()) }
                } label: { Label("More", systemImage: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().disabled(d.bindings.isEmpty)
            }
            TakesList(desk: d)
        }
        .padding(24)
    }

    private func takeHeader(_ t: Take, _ d: JobDesk) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(t.canonicalBasename).font(.headline.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                ProvenanceBadge(provenance: t.provenance)
                if t.isApproved { Badge(text: "APPROVED") }
            }
            Text("\(t.actorDisplayNameSnapshot) · \(t.lineLabel) · Take \(t.perLineTakeNumber) · \(t.productionDate)")
                .foregroundStyle(.secondary)
            Text(t.segmentTextSnapshot).font(.callout).lineLimit(2)
            TakeDetails(take: t)
            if d.missingAudio.contains(t.id) {
                Label("The audio file for this take is missing from the library. The record is intact; restore the file to play or export it.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
    }

    // MARK: Cast

    private func castColumn(_ d: JobDesk) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast").font(.headline)
            if d.bindings.isEmpty { Text("No actor yet.").foregroundStyle(.secondary) }
            ForEach(d.bindings) { b in
                Button { model.selectedBindingID = b.id } label: {
                    HStack {
                        Image(systemName: model.selectedBindingID == b.id ? "largecircle.fill.circle" : "circle")
                        VStack(alignment: .leading) {
                            Text(b.actorDisplayName)
                            Text(voiceLine(b)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                .accessibilityLabel("\(b.actorDisplayName), placeholder voice\(model.selectedBindingID == b.id ? ", selected" : "")")
            }
            let castIDs = Set(d.bindings.map(\.voiceMasterID))
            let uncast = model.voices.filter { !castIDs.contains($0.voice.id) }
            if !uncast.isEmpty {
                Text("Voices in the library").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(uncast) { v in
                    HStack {
                        Text(v.voice.displayName)
                        Spacer()
                        Button("Cast") { model.castVoice(v.voice.id) }.controlSize(.small)
                    }
                }
            }
            Button("Manage Voices…") { model.showVoices = true }.controlSize(.small)
            DisclosureGroup("Stand-in (no voice)") {
                HStack {
                    TextField("Name", text: $newActor).textFieldStyle(.roundedBorder).onSubmit(cast)
                    Button("Add", action: cast).disabled(newActor.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }.font(.caption)
            Spacer()
        }
        .padding(16)
    }
    private func voiceLine(_ b: JobActorBinding) -> String {
        guard let v = model.voices.first(where: { $0.voice.id == b.voiceMasterID }) else { return "Stand-in · no voice" }
        return "\(v.voice.origin == "hostCloned" ? "Cloned" : v.voice.origin.capitalized) · \(v.voice.languageTag ?? "") · Qwen 0.6B"
    }
    private func cast() { let n = newActor; newActor = ""; if !n.trimmingCharacters(in: .whitespaces).isEmpty { model.addActor(named: n) } }
}

struct TakesList: View {
    @Environment(AppModel.self) private var model
    let desk: JobDesk
    var body: some View {
        let groups = Dictionary(grouping: desk.takes, by: \.lineKey).sorted { $0.key < $1.key }
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if groups.isEmpty { Text("No takes yet.").foregroundStyle(.secondary) }
                ForEach(groups, id: \.key) { line, takes in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(CanonicalNaming.lineToken(line)).font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                        FlowRow(takes: takes)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FlowRow: View {
    @Environment(AppModel.self) private var model
    let takes: [Take]
    var body: some View {
        WrapLayout(spacing: 6, lineSpacing: 6) {
            ForEach(takes) { t in
                Button { model.select(take: t.id) } label: {
                    HStack(spacing: 4) {
                        Text("\(t.actorDisplayNameSnapshot) T\(String(format: "%02d", t.perLineTakeNumber))").monospacedDigit()
                        if t.isApproved { Image(systemName: "checkmark.seal.fill").imageScale(.small) }
                        if t.provenance == "mockFixture" { Text("MOCK").font(.caption2.weight(.semibold)) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(model.selectedTakeID == t.id ? AnyShapeStyle(.selection) : AnyShapeStyle(.quaternary.opacity(0.6)), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(t.actorDisplayNameSnapshot), \(t.lineLabel), take \(t.perLineTakeNumber)\(t.isApproved ? ", approved" : "")\(t.provenance == "mockFixture" ? ", mock tone" : "")")
            }
        }
    }
}

/// Left-to-right layout that wraps onto new lines, so every take stays visible.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += lineH + lineSpacing; lineH = 0 }
            x += s.width + spacing; lineH = max(lineH, s.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, width), height: y + lineH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += lineH + lineSpacing; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; lineH = max(lineH, s.height)
        }
    }
}

struct WelcomeBanner: View {
    @Environment(AppModel.self) private var model
    let welcome: AppModel.Welcome
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(welcome.text).font(.title3).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForEach(welcome.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            if let e = welcome.candidate.exportSummary { Text("Delivered as \(e)").font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Make changes today") { model.continueThisJob() }.keyboardShortcut(.defaultAction)
                Button("New job with these settings…") { model.showNewFromSettings = true }
                Spacer()
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45))
    }
}

struct WaveformView: View {
    @Environment(AppModel.self) private var model
    let peaks: [Float]
    let missing: Bool
    var body: some View {
        TimelineView(.animation(paused: !model.isPlaying)) { ctx in
            Canvas { g, size in
                guard !peaks.isEmpty else { return }
                let progress: Double = {
                    guard let s = model.playbackStartedAt, model.playbackDuration > 0 else { return 0 }
                    return min(1, ctx.date.timeIntervalSince(s) / model.playbackDuration)
                }()
                let w = size.width / CGFloat(peaks.count)
                for (i, p) in peaks.enumerated() {
                    let h = max(1, CGFloat(p) * size.height)
                    let rect = CGRect(x: CGFloat(i) * w, y: (size.height - h) / 2, width: max(1, w - 1), height: h)
                    let played = Double(i) / Double(peaks.count) < progress
                    g.fill(Path(rect), with: .style(played ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)))
                }
            }
        }
        .overlay { if missing { Text("Audio missing").foregroundStyle(.secondary) } else if peaks.isEmpty { ProgressView().controlSize(.small) } }
        .accessibilityLabel("Waveform")
    }
}

struct ProvenanceBadge: View {
    let provenance: String
    var body: some View {
        switch provenance {
        case "mockFixture": Badge(text: "MOCK TONE")
        case "importedWAV": Badge(text: "IMPORTED WAV")
        case "render": Badge(text: "QWEN 0.6B")
        default: Badge(text: provenance.uppercased())
        }
    }
}

struct Badge: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold)).tracking(0.4)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.6)))
            .foregroundStyle(.secondary)
    }
}


struct RenderBar: View {
    @Environment(AppModel.self) private var model
    let desk: JobDesk
    @State private var stress = ""

    private var lineName: String {
        guard let id = model.selectedSegmentID, let s = desk.segments.first(where: { $0.id == id }) else { return "Full Read" }
        return "Line \(String(format: "%02d", s.stableLineNumber))"
    }
    private var actorName: String { desk.bindings.first { $0.id == model.selectedBindingID }?.actorDisplayName ?? "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { go(.init()) } label: { Label("Render \(lineName)", systemImage: "waveform.badge.plus") }
                    .buttonStyle(.borderedProminent).keyboardShortcut("r", modifiers: .command).disabled(!model.canRender)
                Group {
                    Button("Again") { go(.init(variation: .fresh, note: "again")) }
                    Button("Livelier") { go(.init(variation: .livelier, note: "livelier")) }
                    Button("Steadier") { go(.init(variation: .steadier, note: "steadier")) }
                }.disabled(!model.canRender)
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 8) {
                TextField("Stress a word (experimental)", text: $stress).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                    .onSubmit(stressRender)
                Button("Render with Stress", action: stressRender).disabled(stress.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer(minLength: 0)
            }
            .disabled(!model.canRender)
            if model.selectedActorIsPlaceholder && !desk.bindings.isEmpty {
                Text("\(actorName) is a stand-in with no voice. Cast a voice to render.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.activeRunsForDesk) { r in
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(runLabel(r)).font(.callout)
                    if let s = r.startedAt { Text(s, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
            }
            if let n = model.latestRenderNote { Label(n, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange) }
        }
    }

    private func runLabel(_ r: RenderRun) -> String {
        let line = desk.segments.first { $0.id == r.segmentID }.map { "Line \(String(format: "%02d", $0.stableLineNumber))" } ?? "Full read"
        let actor = desk.bindings.first { $0.id == r.actorBindingID }?.actorDisplayName ?? ""
        return r.state == "queued" ? "Queued — \(line), \(actor)" : "Rendering \(line) — \(actor)…"
    }
    private func go(_ d: PerformanceDirection) { Task { await model.render(d) } }
    private func stressRender() {
        let w = stress.trimmingCharacters(in: .whitespaces); stress = ""
        if !w.isEmpty { go(.init(emphasis: w.split(separator: " ").map(String.init), note: "stress \(w)")) }
    }
}

struct TakeDetails: View {
    @Environment(AppModel.self) private var model
    let take: Take
    var body: some View {
        if let snap = try? model.library?.snapshot(for: take), take.provenance == "render",
           let resolved = try? JSONDecoder().decode(ResolvedView.self, from: Data(snap.resolvedSettingsJSON.utf8)), let r = resolved.render {
            DisclosureGroup("How this take was made") {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(r.engine.displayName) · \(r.engine.modelRevision)")
                    Text("Voice reference: \(r.referenceLabel) · seed \(r.seed) · \(r.languageTag)")
                    if r.output.textSent != r.scriptText { Text("Text sent: \(r.output.textSent)") }
                    ForEach(r.output.controlsApplied, id: \.self) { Text("• \($0)") }
                    ForEach(r.output.controlsUnsupported, id: \.self) { Text("• Not possible: \($0)").foregroundStyle(.orange) }
                    if let n = r.postProcessing?.note { Text("• \(n)") }
                    Text(String(format: "Engine time %.1f s", r.output.engineSeconds))
                }
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .font(.caption)
        }
    }
    private struct ResolvedView: Decodable { let render: RenderProvenance? }
}


struct EngineerPanel: View {
    @Environment(AppModel.self) private var model
    @State private var typed = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Engineer").font(.headline)
                Spacer()
                if model.engineerConnected {
                    Button("Disconnect") { model.disconnectEngineer() }.controlSize(.small)
                } else {
                    Button("Connect") { Task { await model.connectEngineer() } }.controlSize(.small).buttonStyle(.borderedProminent)
                        .keyboardShortcut("k", modifiers: .command)
                }
            }
            if let e = model.engineer, e.isConnected {
                HStack(spacing: 6) {
                    Circle().fill(stateColour(e.state)).frame(width: 8, height: 8)
                    Text(stateText(e.state)).font(.caption)
                    Spacer()
                    Text(micText).font(.caption2).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Text("Brain: \(model.llmStatus == "ready" ? model.llm.modelName : "rules only (\(model.llmStatus))") · Voice: \(model.engineerVoice.voiceDescription)")
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                if !model.micPartial.isEmpty { Text("“\(model.micPartial)”").font(.callout).italic().foregroundStyle(.secondary) }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(e.log.suffix(40).enumerated()), id: \.offset) { i, t in
                                turn(t).id(i)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: e.log.count) { _, _ in proxy.scrollTo(min(39, e.log.count - 1), anchor: .bottom) }
                }
                HStack(spacing: 6) {
                    TextField("Type a direction…", text: $typed).textFieldStyle(.roundedBorder).onSubmit(send)
                    Button("Send", action: send).disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text(e.latencySummary).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            } else {
                Text("Connect to talk to the Engineer. Everything runs on this Mac — speech recognition, the Engineer's brain and its voice. The microphone is only on while connected.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        }
        .padding(16)
    }

    private func send() { let t = typed; typed = ""; model.typedDirection(t) }

    private var micText: String {
        switch model.mic.status {
        case .off: "mic off"; case .starting: "mic starting"; case .listening: model.mic.onDevice ? "mic on · on-device" : "mic on"
        case .muted: "mic paused"; case .unavailable(let why): why
        }
    }
    private func stateText(_ s: Engineer.State) -> String {
        switch s { case .disconnected: "Disconnected"; case .listening: "Listening"; case .interpreting: "Thinking"; case .working: "Working"; case .speaking: "Speaking" }
    }
    private func stateColour(_ s: Engineer.State) -> Color {
        switch s { case .listening: .green; case .interpreting, .working: .orange; case .speaking: .blue; case .disconnected: .gray }
    }
    @ViewBuilder private func turn(_ t: EngineerTurn) -> some View {
        switch t.speaker {
        case .director: Text("You: \(t.text)").font(.callout)
        case .engineer: Text("Engineer: \(t.text)\(t.latency.map { String(format: "  · %.1f s", $0) } ?? "")").font(.callout).foregroundStyle(.secondary)
        case .system: Text(t.text).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
