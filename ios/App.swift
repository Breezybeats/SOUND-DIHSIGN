import SwiftUI
import UniformTypeIdentifiers

@main
@MainActor
struct SoundDihsignApp: App {
    @StateObject private var model = SynthModel()
    @State private var showsIntroduction = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some Scene {
        WindowGroup {
            ZStack {
                SynthView(model: model)
                    .allowsHitTesting(!showsIntroduction)
                    .accessibilityHidden(showsIntroduction)
                if showsIntroduction {
                    LaunchExperienceView {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                            showsIntroduction = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
                .preferredColorScheme(.light)
                // One root importer serves every studio import action. Stacking
                // separate importers here can leave earlier buttons without a picker.
                .fileImporter(isPresented: $model.isImportingFile, allowedContentTypes: importContentTypes,
                              allowsMultipleSelection: model.fileImportKind == .patch) { result in
                    switch result {
                    case .success(let urls):
                        switch model.fileImportKind {
                        case .patch: model.importPatchFiles(urls)
                        case .sample: if let url = urls.first { model.importSample(from: url) }
                        case .wavetable: if let url = urls.first { model.importWavetable(from: url) }
                        }
                    case .failure(let error):
                        let pickerError = error as NSError
                        if pickerError.domain != NSCocoaErrorDomain || pickerError.code != CocoaError.userCancelled.rawValue {
                            model.status = "Import picker: \(error.localizedDescription)"
                        }
                    }
                }
                .fileExporter(isPresented: $model.isExportingPatch, document: model.exportDocument, contentType: .soundDesignPatch, defaultFilename: model.patch.name) { result in
                    switch result {
                    case .success: model.status = "Patch saved • share it with your Mac using Files or AirDrop"
                    case .failure(let error): model.status = "Export failed: \(error.localizedDescription)"
                    }
                }
                .fileExporter(isPresented: Binding(get: { model.isExportingFXP && !model.showPresetLibrary }, set: { model.isExportingFXP = $0 }), document: model.fxpExportDocument, contentType: .serumPresetFile, defaultFilename: model.patch.name) { result in
                    switch result {
                    case .success: model.status = "Serum FXP saved. Loading in Serum still needs verification."
                    case .failure(let error): model.status = "Serum export failed: \(error.localizedDescription)"
                    }
                }
                .onOpenURL { url in
                    model.importPatchFiles([url])
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { model.stopAudio() }
                }
        }
    }

    private var importContentTypes: [UTType] {
        switch model.fileImportKind {
        case .patch: return [.soundDesignPatch, .serumPresetFile, .json, .data]
        case .sample: return [.audio]
        case .wavetable: return [.wav]
        }
    }
}
