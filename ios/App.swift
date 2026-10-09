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
                .fileImporter(isPresented: $model.isImportingSample, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls): if let url = urls.first { model.importSample(from: url) }
                    case .failure(let error): model.status = "Sample picker: \(error.localizedDescription)"
                    }
                }
                .fileImporter(isPresented: $model.isImportingPatch, allowedContentTypes: [.soundDesignPatch, .json], allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls): if let url = urls.first { model.loadPatch(from: url) }
                    case .failure(let error): model.status = "Patch picker: \(error.localizedDescription)"
                    }
                }
                .fileImporter(isPresented: $model.isImportingWavetable, allowedContentTypes: [.wav], allowsMultipleSelection: false) { result in
                    switch result {
                    case .success(let urls): if let url = urls.first { model.importWavetable(from: url) }
                    case .failure(let error): model.status = "Wavetable picker: \(error.localizedDescription)"
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
                    if url.pathExtension.lowercased() == "fxp" { model.importPresetFiles([url]) }
                    else { model.loadPatch(from: url) }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { model.stopAudio() }
                }
        }
    }
}
