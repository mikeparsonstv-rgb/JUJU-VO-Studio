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
                    castColumn(d).frame(width: 240)
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
            Label("Engineer: not connected (Stage 3)", systemImage: "person.wave.2").font(.caption).foregroundStyle(.secondary)
                .accessibilityLabel("Engineer not connected. Arrives in Stage 3.")
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
                    Button { model.exportSelected() } label: { Label("Export WAV…", systemImage: "square.and.arrow.up") }
                        .keyboardShortcut("e", modifiers: .command).disabled(d.missingAudio.contains(t.id))
                    Spacer()
                }
                if let exports = d.exportsByTake[t.id], !exports.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delivered").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(exports) { e in
                            Text("\(e.exportedName) · \(e.sampleRate) Hz · \(e.bitDepth)-bit · \(e.exportedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            } else {
                ContentUnavailableView("No take selected", systemImage: "waveform", description: Text(d.bindings.isEmpty ? "Cast an actor, then add a take." : "Add a take for the selected line."))
                    .frame(height: 220)
            }
            Divider()
            HStack {
                Text("Takes").font(.headline)
                Spacer()
                Button { model.addTakeFromWAV() } label: { Label("Add Take from WAV…", systemImage: "square.and.arrow.down") }
                    .disabled(d.bindings.isEmpty)
                Button { model.addTake(.mockTone()) } label: { Label("Add Mock Take", systemImage: "tuningfork") }
                    .disabled(d.bindings.isEmpty).help("Generates a labelled test tone — not a voice, not a render.")
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
                            Text("Placeholder voice · no renderer").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                .accessibilityLabel("\(b.actorDisplayName), placeholder voice\(model.selectedBindingID == b.id ? ", selected" : "")")
            }
            HStack {
                TextField("Actor name", text: $newActor).textFieldStyle(.roundedBorder).onSubmit(cast)
                Button("Cast", action: cast).disabled(newActor.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer()
            Text("Stage 1: actors are placeholders and takes are imported WAVs or labelled mock tones. Real voices arrive in Stage 2.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(16)
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
