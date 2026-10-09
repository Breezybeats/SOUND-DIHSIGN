import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var soundDesignPatch: UTType { UTType(exportedAs: "com.breezybeats.sounddihsign.patch", conformingTo: .json) }
}

struct PatchDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.soundDesignPatch, .json] }
    static var writableContentTypes: [UTType] { [.soundDesignPatch] }
    var patch: SoundPatch

    init(patch: SoundPatch = .initial) { self.patch = patch }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= SoundPatch.maximumFileBytes else {
            throw PatchError.invalid("Choose a SOUND/DIHSIGN patch smaller than 32 MB.")
        }
        patch = try JSONDecoder().decode(SoundPatch.self, from: data).validated()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(patch.validated())
        guard data.count <= SoundPatch.maximumFileBytes else {
            throw PatchError.invalid("This patch exceeds the 32 MB sharing limit. Use shorter samples or fewer wavetable frames.")
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
