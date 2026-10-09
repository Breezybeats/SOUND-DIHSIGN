import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let soundDihsignPatch = UTType(exportedAs: "com.breezybeats.sounddihsign.patch", conformingTo: .json)
}

enum CompanionError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

struct CompanionLibraryEntry: Identifiable, Sendable {
    let url: URL
    let patch: SoundPatch
    var id: String { url.lastPathComponent }
}

enum CompanionStore {
    static var maximumPatchBytes: Int { SoundPatch.maximumFileBytes }

    static func libraryDirectory() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("SOUND-DIHSIGN/Library", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Imported files are untrusted. Read at most the shared limit plus one byte, then let
    /// the shared schema reject unknown IDs, nonfinite values, and invalid samples.
    static func readPatch(at url: URL) throws -> SoundPatch {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let resource = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard resource.isRegularFile == true else {
            throw CompanionError.message("Choose a .sdpatch file, not a folder.")
        }
        if let size = resource.fileSize, size > maximumPatchBytes {
            throw CompanionError.message("This patch exceeds the 32 MiB import limit.")
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: maximumPatchBytes + 1) ?? Data()
        guard !data.isEmpty, data.count <= maximumPatchBytes else {
            throw CompanionError.message("This patch is empty or exceeds the 32 MiB import limit.")
        }
        do {
            return try JSONDecoder().decode(SoundPatch.self, from: data).validated()
        } catch {
            throw CompanionError.message("Could not import this SOUND DIHSIGN patch: \(error.localizedDescription)")
        }
    }

    static func encoded(_ patch: SoundPatch) throws -> Data {
        let validated = try patch.validated()
        let encoder = JSONEncoder()
        // Match the phone's compact encoding; formatting should not inflate a
        // valid near-limit imported patch beyond the shared transfer limit.
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(validated)
        guard data.count <= maximumPatchBytes else {
            throw CompanionError.message("This patch exceeds the 32 MiB export limit.")
        }
        return data
    }

    static func save(_ patch: SoundPatch) throws -> CompanionLibraryEntry {
        let patch = try patch.validated()
        let url = try libraryDirectory().appendingPathComponent("\(UUID().uuidString).sdpatch")
        try encoded(patch).write(to: url, options: .atomic)
        return CompanionLibraryEntry(url: url, patch: patch)
    }

    static func readLibrary() throws -> (entries: [CompanionLibraryEntry], invalidCount: Int) {
        let urls = try FileManager.default.contentsOfDirectory(at: libraryDirectory(),
                                                               includingPropertiesForKeys: [.fileSizeKey],
                                                               options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "sdpatch" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var entries: [CompanionLibraryEntry] = []
        var invalidCount = 0
        for url in urls {
            do {
                entries.append(CompanionLibraryEntry(url: url, patch: try readPatch(at: url)))
            } catch { invalidCount += 1 }
        }
        return (entries, invalidCount)
    }

    static func filename(_ name: String) -> String {
        let cleaned = name.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
        }
        let result = String(cleaned.prefix(80))
        return result.isEmpty ? "Sound_Dihsign_Patch" : result
    }
}

@MainActor
final class CompanionModel: ObservableObject {
    @Published var library: [CompanionLibraryEntry] = []
    @Published var selectedID: String? {
        didSet {
            if selectedID != oldValue {
                stopPreview()
                clearRenderedAudio()
            }
        }
    }
    @Published var showImporter = false
    @Published var isImporting = false
    @Published var isRendering = false
    @Published var isPlaying = false
    @Published var renderedURL: URL?
    @Published var status = "Import a .sdpatch from your iPhone to begin."
    @Published var errorMessage: String?
    @Published var previewNote = 36 {
        didSet { stopPreview(); clearRenderedAudio() }
    }
    @Published var noteDuration = 2.0 {
        didSet { clearRenderedAudio() }
    }
    private let preview = CompanionAudioPreview()
    private var renderToken = UUID()
    private var completedRenderFiles: [URL] = []

    var selectedPatch: SoundPatch? { library.first { $0.id == selectedID }?.patch }

    init() {
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try CompanionStore.readLibrary()
                }.value
                let existingIDs = Set(library.map(\.id))
                library.append(contentsOf: result.entries.filter { !existingIDs.contains($0.id) })
                if selectedID == nil { selectedID = library.first?.id }
                if result.invalidCount > 0 {
                    status = "Loaded \(library.count) patches. \(result.invalidCount) invalid library files were skipped."
                } else if !library.isEmpty {
                    status = "Loaded \(library.count) local patches."
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func importFile(_ url: URL) {
        guard !isImporting else { return }
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                let entry = try await Task.detached(priority: .userInitiated) {
                    try CompanionStore.save(CompanionStore.readPatch(at: url))
                }.value
                library.insert(entry, at: 0)
                selectedID = entry.id
                status = "Imported \(entry.patch.name). The original file is unchanged."
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func addInitialPatch() {
        do {
            let entry = try CompanionStore.save(SoundPatch.initial)
            library.insert(entry, at: 0)
            selectedID = entry.id
            status = "Init patch added. Preview it or import a patch from your phone."
        } catch { errorMessage = error.localizedDescription }
    }

    func removeSelected() {
        guard let entry = library.first(where: { $0.id == selectedID }) else { return }
        do {
            try FileManager.default.removeItem(at: entry.url)
            library.removeAll { $0.id == entry.id }
            selectedID = library.first?.id
            status = "Removed the local library copy."
        } catch { errorMessage = error.localizedDescription }
    }

    func togglePreview() {
        if isPlaying { stopPreview(); return }
        guard let patch = selectedPatch else { return }
        do {
            try preview.start(patch: patch, note: previewNote)
            isPlaying = true
            status = "Playing \(Self.noteName(previewNote)). Use Stop / Panic to stop."
        } catch {
            preview.stop()
            errorMessage = error.localizedDescription
        }
    }

    func stopPreview() {
        preview.stop()
        if isPlaying { status = "Preview stopped." }
        isPlaying = false
    }

    func renderWAV() {
        guard let patch = selectedPatch, !isRendering else { return }
        stopPreview()
        clearRenderedAudio()
        isRendering = true
        let token = UUID()
        renderToken = token
        let note = previewNote
        let duration = noteDuration
        Task {
            defer { isRendering = false }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try CompanionWaveRenderer.render(patch: patch, note: note, holdSeconds: duration)
                }.value
                guard renderToken == token else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                completedRenderFiles.append(url)
                renderedURL = url
                status = "WAV ready: stereo 48 kHz / 16-bit PCM, with a release and delay tail."
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func exportPatch() {
        guard let patch = selectedPatch else { return }
        do {
            let data = try CompanionStore.encoded(patch)
            try save(data: data, name: CompanionStore.filename(patch.name) + ".sdpatch", type: .soundDihsignPatch)
        } catch { errorMessage = error.localizedDescription }
    }

    func saveRenderedWAV() {
        guard let url = renderedURL, let patch = selectedPatch else { return }
        do {
            let data = try Data(contentsOf: url)
            try save(data: data, name: CompanionStore.filename(patch.name) + ".wav", type: .wav)
        } catch { errorMessage = error.localizedDescription }
    }

    func exportRecipe() {
        guard let patch = selectedPatch else { return }
        let text = CompanionRecipe.make(patch)
        do {
            try save(data: Data(text.utf8), name: CompanionStore.filename(patch.name) + "_recipe.txt", type: .plainText)
        } catch { errorMessage = error.localizedDescription }
    }

    private func save(data: Data, name: String, type: UTType) throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try data.write(to: url, options: .atomic)
        status = "Saved \(url.lastPathComponent)."
    }

    private func clearRenderedAudio() {
        renderToken = UUID()
        // Keep completed files alive for pending Finder/Serum drag operations.
        // They reside in the app's temporary directory and are cleaned on exit.
        renderedURL = nil
    }

    deinit {
        for url in completedRenderFiles { try? FileManager.default.removeItem(at: url) }
    }

    static func noteName(_ midi: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[midi % 12])\(midi / 12 - 1)"
    }
}

enum CompanionRecipe {
    static func make(_ patch: SoundPatch) -> String {
        var lines = [
            "SOUND DIHSIGN patch recipe: \(patch.name)",
            "Schema version: \(patch.schemaVersion)",
            "",
            "This describes SOUND DIHSIGN's engine, not a native Serum preset.",
            "Use it as a starting point for a manual rebuild. Oscillator algorithms,",
            "parameter scales, modulation and effects can differ in Serum.",
            "A rendered WAV contains the resulting audio, not editable effects.",
            "",
            "PARAMETERS"
        ]
        for descriptor in ParameterCatalog.descriptors {
            let value = patch.parameters[String(descriptor.id)] ?? descriptor.defaultValue
            lines.append("\(descriptor.id) · \(descriptor.name): \(String(format: "%.5g", Double(value)))")
        }
        lines.append(contentsOf: ["", "MODULATION ROUTES"])
        let sources = ["None", "LFO 1", "Envelope 1", "Velocity", "Macro 1"]
        if patch.routes.isEmpty { lines.append("No routes assigned.") }
        for route in patch.routes.sorted(by: { $0.slot < $1.slot }) {
            let source = sources.indices.contains(route.source) ? sources[route.source] : "Source \(route.source)"
            lines.append("Slot \(route.slot + 1): \(source) → \(ParameterCatalog.name(route.destination)), amount \(route.amount)")
        }
        lines.append(contentsOf: ["", "EMBEDDED SAMPLES"])
        if patch.samples.isEmpty { lines.append("None.") }
        for sample in patch.samples {
            lines.append("Oscillator \(sample.oscillator + 1): \(sample.samples.count) mono samples, \(sample.sampleRate) Hz.")
        }
        lines.append(contentsOf: ["", "EMBEDDED WAVETABLES"])
        if patch.wavetables.isEmpty { lines.append("None. Built-in generated wavetables are used.") }
        for table in patch.wavetables {
            lines.append("Oscillator \(table.oscillator + 1): \(table.samples.count / table.frameSize) frames, \(table.frameSize) samples per frame.")
        }
        lines.append(contentsOf: ["", "SERUM TRANSFER",
            "Native SerumPreset export is unavailable. Import the rendered WAV into",
            "Serum's sample oscillator as a one-shot, or rebuild with this recipe.",
            "Keep the .sdpatch for editable SOUND DIHSIGN parameters and routing."
        ])
        return lines.joined(separator: "\n") + "\n"
    }
}
