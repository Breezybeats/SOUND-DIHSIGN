import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum CompanionStyle {
    static let background = Color(red: 0.035, green: 0.045, blue: 0.075)
    static let surface = Color(red: 0.075, green: 0.085, blue: 0.13)
    static let cyan = Color(red: 0.23, green: 0.87, blue: 0.88)
    static let violet = Color(red: 0.67, green: 0.48, blue: 1.0)
}

@MainActor
struct CompanionView: View {
    @ObservedObject var model: CompanionModel
    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                library
                    .frame(minWidth: 230, idealWidth: 260, maxWidth: 320)
                ScrollView {
                    if let patch = model.selectedPatch {
                        patchDetail(patch)
                    } else {
                        emptyState
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(CompanionStyle.cyan)
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.isImporting || model.isRendering { ProgressView().controlSize(.small) }
            }
            .padding(12)
        }
        .background(CompanionStyle.background)
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(CompanionStyle.cyan, style: StrokeStyle(lineWidth: 3, dash: [10]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget, perform: receiveDrop)
        .onOpenURL { url in
            if url.isFileURL { model.importFile(url) }
        }
        .fileImporter(isPresented: $model.showImporter,
                      allowedContentTypes: [.soundDihsignPatch, .json, .data]) { result in
            switch result {
            case .success(let url): model.importFile(url)
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .alert("Could not complete the operation", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onDisappear { model.stopPreview() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.path")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(CompanionStyle.cyan)
            VStack(alignment: .leading, spacing: 4) {
                Text("SOUND DIHSIGN").font(.system(size: 21, weight: .bold, design: .monospaced))
                Text("MAC COMPANION · Your sounds, ready for the studio")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.showImporter = true } label: {
                Label("Import patch", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(CompanionStyle.violet)
            .disabled(model.isImporting)
        }
        .padding(20)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PATCH LIBRARY").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.library.count)").font(.caption.monospacedDigit())
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            if model.library.isEmpty {
                Text("Your imported patches appear here. This library stays on this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
            List(selection: $model.selectedID) {
                ForEach(model.library) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.patch.name).font(.body.weight(.medium)).lineLimit(2)
                        Text("\(entry.patch.routes.count) modulation routes · \(entry.patch.samples.count) samples")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                    .tag(entry.id)
                }
            }
            .scrollContentBackground(.hidden)
            HStack {
                Button("Try Init patch", systemImage: "plus") { model.addInitialPatch() }
                Spacer()
                Button { model.removeSelected() } label: { Image(systemName: "trash") }
                    .help("Remove the selected library copy; the original file stays untouched.")
                    .disabled(model.selectedPatch == nil)
            }
            .padding(16)
        }
        .background(CompanionStyle.surface.opacity(0.5))
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 58)).foregroundStyle(CompanionStyle.cyan)
            Text("From your pocket to your studio")
                .font(.system(size: 27, weight: .semibold))
            Text("Export a .sdpatch on your iPhone. Send it with AirDrop or save it in Files, then import or drop the file here.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 440)
            HStack(spacing: 12) {
                Button("Import patch") { model.showImporter = true }
                    .buttonStyle(.borderedProminent).tint(CompanionStyle.violet)
                Button("Try Init patch") { model.addInitialPatch() }
            }
            Text("Preview patches here, render a WAV, and drag the audio into Serum's sample oscillator.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 430)
        }
        .frame(maxWidth: .infinity, minHeight: 470)
        .padding(30)
    }

    private func patchDetail(_ patch: SoundPatch) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(patch.name).font(.system(size: 30, weight: .bold))
                Text("Editable in SOUND DIHSIGN · \(patch.routes.count) modulation routes")
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<3) { oscillator in
                    oscillatorCard(patch, oscillator: oscillator)
                }
            }
            previewCard
            exportCard
            modulationCard(patch)
            VStack(alignment: .leading, spacing: 10) {
                Label("Studio transfer", systemImage: "desktopcomputer").font(.headline)
                Text("Native SerumPreset export is unavailable. A WAV transfers the sound as audio; its effects are baked in. Export the recipe to guide a manual rebuild in Serum, and keep the .sdpatch for editing in SOUND DIHSIGN.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(CompanionStyle.surface, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(26)
        .frame(maxWidth: 1050, alignment: .leading)
    }

    private func oscillatorCard(_ patch: SoundPatch, oscillator: Int) -> some View {
        let base = oscillator * 32
        let mode = Int(patch.parameters[String(base)] ?? 0)
        let modes = ["Wavetable", "Sample", "Granular", "Spectral"]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("OSC \(["A", "B", "C"][oscillator])").font(.caption.weight(.bold))
                Spacer()
                Image(systemName: "waveform").foregroundStyle(CompanionStyle.cyan)
            }
            Text(modes.indices.contains(mode) ? modes[mode] : "Unknown mode")
                .font(.headline)
            HStack {
                Text("Level").foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", Double(patch.parameters[String(base + 3)] ?? 0)))
                    .monospacedDigit()
            }
            .font(.caption)
            HStack {
                Text("Semitones").foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f", Double(patch.parameters[String(base + 4)] ?? 0)))
                    .monospacedDigit()
            }
            .font(.caption)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompanionStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Audition", systemImage: "speaker.wave.2").font(.headline)
            HStack(spacing: 14) {
                Picker("Note", selection: $model.previewNote) {
                    ForEach([24, 36, 48, 60, 72], id: \.self) { note in
                        Text(CompanionModel.noteName(note)).tag(note)
                    }
                }
                .frame(width: 145)
                Button { model.togglePreview() } label: {
                    Label(model.isPlaying ? "Stop / Panic" : "Play preview",
                          systemImage: model.isPlaying ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isPlaying ? .pink : CompanionStyle.cyan)
                Spacer()
                if model.isPlaying {
                    Label("Playing", systemImage: "waveform").font(.caption)
                        .foregroundStyle(CompanionStyle.cyan)
                }
            }
            Text("The preview sustains until stopped. ⌘. stops all notes.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(CompanionStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Export for the studio", systemImage: "square.and.arrow.up").font(.headline)
            HStack {
                Text("Note length").font(.callout)
                Slider(value: $model.noteDuration, in: 0.25...8, step: 0.25)
                    .tint(CompanionStyle.violet)
                Text(String(format: "%.2f s", model.noteDuration))
                    .font(.caption.monospacedDigit()).frame(width: 58)
            }
            HStack(spacing: 12) {
                Button(model.isRendering ? "Rendering…" : "Render WAV", systemImage: "waveform") {
                    model.renderWAV()
                }
                .buttonStyle(.borderedProminent).tint(CompanionStyle.violet)
                .disabled(model.isRendering)
                Button("Save .sdpatch") { model.exportPatch() }
                Button("Save recipe") { model.exportRecipe() }
            }
            if let url = model.renderedURL {
                HStack(spacing: 14) {
                    Label("Drag WAV into Serum", systemImage: "hand.draw")
                        .font(.callout.weight(.medium))
                        .padding(.vertical, 12).padding(.horizontal, 16)
                        .background(CompanionStyle.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CompanionStyle.cyan.opacity(0.4)))
                        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL) }
                        .help("Drag the actual WAV file onto a sample oscillator or into Finder.")
                    Button("Save WAV…") { model.saveRenderedWAV() }
                }
            }
            Text("Render includes the app's effects and a release/delay tail. WAV: stereo 48 kHz, 16-bit PCM.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(CompanionStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func modulationCard(_ patch: SoundPatch) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Modulation routing", systemImage: "point.3.connected.trianglepath.dotted").font(.headline)
            if patch.routes.isEmpty {
                Text("No routes assigned.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(Array(patch.routes.enumerated()), id: \.offset) { _, route in
                    let sources = ["None", "LFO 1", "Envelope 1", "Velocity", "Macro 1"]
                    let source = sources.indices.contains(route.source) ? sources[route.source] : "Source \(route.source)"
                    HStack {
                        Text(source).foregroundStyle(CompanionStyle.cyan)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(ParameterCatalog.name(route.destination))
                        Spacer()
                        Text(String(format: "%+.2f", Double(route.amount))).monospacedDigit()
                    }
                    .font(.callout)
                }
            }
        }
        .padding(18)
        .background(CompanionStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !model.isImporting,
              let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            let url: URL?
            if let fileURL = item as? URL { url = fileURL }
            else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else { url = nil }
            Task { @MainActor in
                if let url, url.isFileURL { model.importFile(url) }
                else { model.errorMessage = error?.localizedDescription ?? "Drop a local .sdpatch file here." }
            }
        }
        return true
    }
}
