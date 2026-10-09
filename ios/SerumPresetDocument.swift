import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let serumPresetFile = UTType(importedAs: "com.breezybeats.sounddihsign.serum-fxp", conformingTo: .data)
}

/// Export of an experimentally randomized legacy Serum FXP state. Playback
/// and loading in licensed Serum still require host validation.
struct SerumPresetDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.serumPresetFile] }
    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents,
              !contents.isEmpty, contents.count <= SoundPatch.maximumFileBytes else {
            throw PatchError.invalid("Choose a Serum FXP smaller than 32 MB.")
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard !data.isEmpty, data.count <= SoundPatch.maximumFileBytes else {
            throw PatchError.invalid("Generate from Serum presets before exporting a Serum FXP.")
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
