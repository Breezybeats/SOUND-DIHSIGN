import SwiftUI

@main
@MainActor
struct SoundDihsignCompanionApp: App {
    @StateObject private var model = CompanionModel()

    var body: some Scene {
        WindowGroup {
            CompanionView(model: model)
                .frame(minWidth: 860, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import SOUND DIHSIGN Patch…") { model.showImporter = true }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Stop All Notes") { model.stopPreview() }
                    .keyboardShortcut(".", modifiers: .command)
            }
        }
    }
}
