import SwiftUI
import UniformTypeIdentifiers

@main
@MainActor
struct SoundDihsignApp: App {
    @StateObject private var model = SynthModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            SynthView(model: model)
                .preferredColorScheme(.dark)
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
                .onOpenURL { model.loadPatch(from: $0) }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { model.stopAudio() }
                }
        }
    }
}
