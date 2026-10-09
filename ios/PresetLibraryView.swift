import SwiftUI
import UniformTypeIdentifiers

/// Presets stay in this device's private app storage. A checkmark chooses a
/// donor for Generate; the play button loads one preset for keyboard audition.
@MainActor
struct PresetLibraryView: View {
    @ObservedObject var model: SynthModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var showLocks = false

    private var visiblePresets: [LibraryPreset] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.library.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var selectedCount: Int {
        model.library.filter { model.selectedPresetIDs.contains($0.id) }.count
    }

    private var busy: Bool { model.isImportingPresets || model.isRandomizing }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                                .frame(width: 48, height: 48)
                                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your sounds, new combinations")
                                    .font(.headline)
                                Text("Choose presets, then generate a remix.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            Button {
                                model.isImportingPresetFiles = true
                            } label: {
                                Label("Import presets", systemImage: "plus")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            Button {
                                model.addCurrentPatchToLibrary()
                            } label: {
                                Image(systemName: "tray.and.arrow.down")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Save current sound to the pool")
                        }
                        .disabled(busy)
                        if model.isImportingPresets {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Adding presets…").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        if !busy, !model.status.isEmpty, model.status != "Ready to make a sound", !model.status.hasPrefix("Audio on") {
                            Text(model.status)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Import .fxp or .sdpatch files from Files. Your library stays on this device.")
                }

                Section {
                    Button {
                        model.randomizeFromSelection()
                    } label: {
                        HStack {
                            if model.isRandomizing { ProgressView().tint(.white) }
                            else { Image(systemName: "shuffle") }
                            Text(model.isRandomizing ? "Mixing…" : "Generate remix")
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(selectedCount)")
                                .font(.subheadline.monospacedDigit())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.white.opacity(0.18), in: Capsule())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .background(Color.blue.opacity(selectedCount == 0 || busy ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCount == 0 || busy)

                    if selectedCount == 1 {
                        Text("Choose two or more presets for new combinations. One preset keeps its existing stored values.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if !model.lastRandomizationSummary.isEmpty {
                        Text(model.lastRandomizationSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button {
                                model.undoRandomization()
                            } label: {
                                Label("Undo", systemImage: "arrow.uturn.backward")
                                    .frame(minHeight: 44)
                            }
                            .disabled(!model.canUndoRandomization || busy)
                            Spacer()
                            Button("Play on keyboard") {
                                dismiss()
                            }
                            .frame(minHeight: 44)
                        }
                    }
                    if model.canExportFXP {
                        Button {
                            model.isExportingFXP = true
                        } label: {
                            Label("Export experimental FXP", systemImage: "square.and.arrow.up")
                                .frame(minHeight: 44)
                        }
                        .disabled(busy)
                    }
                } footer: {
                    Text("Serum mixes use stored Serum controls. The iPhone plays a simplified preview; check experimental FXP exports in Serum.")
                }

                Section {
                    DisclosureGroup(isExpanded: $showLocks) {
                        ForEach(ParameterCatalog.descriptors, id: \.id) { descriptor in
                            Button {
                                model.toggleParameterLock(id: descriptor.id)
                            } label: {
                                HStack {
                                    Text(descriptor.name).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: model.lockedParameters.contains(descriptor.id) ? "lock.fill" : "lock.open")
                                        .foregroundStyle(model.lockedParameters.contains(descriptor.id) ? Color.blue : Color.secondary)
                                        .frame(width: 44, height: 44)
                                }
                            }
                            .disabled(busy)
                            .accessibilityLabel("\(descriptor.name), \(model.lockedParameters.contains(descriptor.id) ? "kept fixed" : "can change")")
                            .accessibilityHint("Double tap to change whether this control is randomized")
                        }
                    } label: {
                        Label("Keep controls fixed (\(model.lockedParameters.count))", systemImage: "lock")
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                } footer: {
                    Text("A fixed oscillator mode or table also keeps its audio asset. Locked or mixed app-patch remixes export as .sdpatch.")
                }

                Section {
                    if model.library.isEmpty {
                        ContentUnavailableView {
                            Label("Start your sound pool", systemImage: "waveform")
                        } description: {
                            Text("Import your Serum presets or save the sound you are making.")
                        }
                        .listRowSeparator(.hidden)
                    } else if visiblePresets.isEmpty {
                        Text("No presets match your search.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visiblePresets) { entry in
                            presetRow(entry)
                        }
                    }
                } header: {
                    HStack {
                        Text("\(selectedCount) selected · \(model.library.count) presets")
                        Spacer()
                        Button("All") { model.selectAllPresets() }
                            .frame(minWidth: 44, minHeight: 44)
                            .disabled(model.library.isEmpty || busy)
                        Button("Clear") { model.clearPresetSelection() }
                            .frame(minWidth: 44, minHeight: 44)
                            .disabled(selectedCount == 0 || busy)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .listStyle(.insetGrouped)
            .navigationTitle("Sound pool")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Find a preset")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(.blue)
        .preferredColorScheme(.light)
        .fileImporter(isPresented: $model.isImportingPresetFiles,
                      allowedContentTypes: [.serumPresetFile, .soundDesignPatch, .json, .data],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): model.importPresetFiles(urls)
            case .failure(let error): model.status = "Preset picker: \(error.localizedDescription)"
            }
        }
        .fileExporter(isPresented: $model.isExportingFXP, document: model.fxpExportDocument,
                      contentType: .serumPresetFile, defaultFilename: model.patch.name) { result in
            switch result {
            case .success: model.status = "Serum FXP saved. Loading in Serum still needs verification."
            case .failure(let error): model.status = "Serum export failed: \(error.localizedDescription)"
            }
        }
    }

    private func presetRow(_ entry: LibraryPreset) -> some View {
        HStack(spacing: 4) {
            Button {
                model.togglePresetSelection(id: entry.id)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.selectedPresetIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(model.selectedPresetIDs.contains(entry.id) ? Color.blue : Color.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(entry.fileKind.displayName + (entry.isPartialPreview ? " · simplified preview" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityLabel("\(entry.name), \(model.selectedPresetIDs.contains(entry.id) ? "selected" : "not selected")")
            .accessibilityHint("Double tap to choose this preset for generation")
            Button {
                model.auditionPreset(id: entry.id)
            } label: {
                Image(systemName: "play.circle")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(busy)
            .accessibilityLabel("Load \(entry.name) for keyboard audition")
            NavigationLink {
                PresetLibraryDetail(entry: entry)
            } label: {
                Image(systemName: "info.circle")
                    .font(.body)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details for \(entry.name)")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                model.removePreset(id: entry.id)
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .disabled(busy)
        }
    }
}

@MainActor
private struct PresetLibraryDetail: View {
    let entry: LibraryPreset

    var body: some View {
        List {
            Section {
                LabeledContent("Source", value: entry.fileKind.displayName)
                if !entry.author.isEmpty { LabeledContent("Author", value: entry.author) }
                LabeledContent("Available app controls", value: String(entry.availableControlCount))
                if entry.storedControlCount > 0 {
                    LabeledContent("Stored Serum controls", value: String(entry.storedControlCount))
                }
                LabeledContent("Preview connections", value: String(entry.routes.count))
            }
            Section("Oscillator assets") {
                ForEach(0..<3, id: \.self) { oscillator in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Oscillator \(["A", "B", "C"][oscillator])")
                            Spacer()
                            Text(assetDescription(oscillator))
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        if !entry.tableNames[oscillator].isEmpty {
                            Text(entry.tableNames[oscillator])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            if entry.isPartialPreview {
                Section("Preview in this app") {
                    Text("The app translates supported settings. Serum's oscillator algorithms, effects, custom LFOs and some connections sound different or are unavailable. Missing external wavetables are muted rather than replaced.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !entry.warnings.isEmpty {
                Section("Preset notes") {
                    ForEach(Array(entry.warnings.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.white)
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func assetDescription(_ oscillator: Int) -> String {
        if entry.tableFrameCounts[oscillator] > 0 { return "\(entry.tableFrameCounts[oscillator]) table frames" }
        if entry.sampleFrameCounts[oscillator] > 0 { return "Sample available" }
        if entry.fileKind == .sdpatch { return "Built-in / unused" }
        if oscillator == 2 { return "Unused in Serum 1" }
        return "No embedded table"
    }
}
