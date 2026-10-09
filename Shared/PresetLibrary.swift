import Foundation
import SoundCore

public enum PresetFileKind: String, Codable, Sendable {
    case fxp
    case sdpatch

    public var displayName: String { self == .fxp ? "Serum FXP" : "App patch" }
}

/// Small, persistent index entry. Audio assets remain in the private original
/// file and are decoded only when auditioning or choosing assets for a remix.
public struct LibraryPreset: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let fileKind: PresetFileKind
    public let relativeFilename: String
    public let parameters: [String: Float]
    public let rawParameters: [Float]
    public let routes: [ModulationRoute]
    public let warnings: [String]
    public let tableFrameCounts: [Int]
    public let sampleFrameCounts: [Int]
    public let tableNames: [String]
    public let author: String
    public let importedAt: Date
    /// Duplicate detection only, followed by a full byte comparison. This is
    /// deliberately not used as a security or integrity guarantee.
    public let sourceFingerprint: String?

    public var availableControlCount: Int { parameters.count }
    public var storedControlCount: Int { rawParameters.count }
    public var isPartialPreview: Bool { fileKind == .fxp }
}

public struct PresetRandomization: Sendable {
    public let patch: SoundPatch
    public let summary: String
    /// Present only for an unlocked pool consisting entirely of Serum FXPs.
    /// Experimental: independently checked container, not a Serum host test.
    public let fxpData: Data?
}

/// Personal library. The app never bundles or uploads imported preset banks.
/// Call these synchronous operations serially on a background task.
public enum PresetLibraryStore {
    public static let maximumEntries = 512
    private static let maximumMetadataBytes = 256 * 1_024

    private static var directory: URL {
        #if SOUND_DIHSIGN_TESTING
        if let testPath = ProcessInfo.processInfo.environment["SOUND_DIHSIGN_TEST_LIBRARY_PATH"], !testPath.isEmpty {
            return URL(fileURLWithPath: testPath, isDirectory: true)
        }
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SoundDihsign", isDirectory: true)
            .appendingPathComponent("PersonalPresets", isDirectory: true)
    }

    public static func loadLibrary() throws -> [LibraryPreset] {
        try prepareDirectory()
        let files = try metadataFiles()
        guard files.count <= maximumEntries else { throw PatchError.invalid("The personal library is limited to 512 presets.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try files.map { url in
            let data = try boundedData(url, limit: maximumMetadataBytes)
            let entry = try decoder.decode(LibraryPreset.self, from: data)
            try validateEntry(entry)
            return entry
        }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public static func importFile(_ url: URL) throws -> LibraryPreset {
        #if os(iOS) || os(macOS)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        #endif
        guard let kind = PresetFileKind(rawValue: url.pathExtension.lowercased()) else {
            throw PatchError.invalid("Choose Serum .fxp presets or SOUND DIHSIGN .sdpatch files.")
        }
        let data = try boundedData(url, limit: SoundPatch.maximumFileBytes)
        return try store(data: data, kind: kind)
    }

    public static func savePatch(_ patch: SoundPatch) throws -> LibraryPreset {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(patch.validated())
        guard data.count <= SoundPatch.maximumFileBytes else {
            throw PatchError.invalid("This patch exceeds the 32 MB personal-preset limit.")
        }
        return try store(data: data, kind: .sdpatch)
    }

    public static func loadPatch(_ entry: LibraryPreset) throws -> SoundPatch {
        try validateEntry(entry)
        let data = try originalData(entry)
        if entry.fileKind == .sdpatch {
            return try JSONDecoder().decode(SoundPatch.self, from: data).validated()
        }
        return try readSerum(data, includeAssets: true).patch
    }

    public static func remove(_ entry: LibraryPreset) throws {
        try validateEntry(entry)
        let original = directory.appendingPathComponent(entry.relativeFilename)
        let metadata = directory.appendingPathComponent("\(entry.id).json")
        let manager = FileManager.default
        // These paths contain only a validated UUID and the known extension.
        // The user's file in Files is never removed.
        if manager.fileExists(atPath: original.path) { try manager.removeItem(at: original) }
        if manager.fileExists(atPath: metadata.path) { try manager.removeItem(at: metadata) }
    }

    public static func randomize(entries: [LibraryPreset], current: SoundPatch, locked: Set<Int>) throws -> PresetRandomization {
        guard !entries.isEmpty, entries.count <= maximumEntries else {
            throw PatchError.invalid("Select at least one preset before generating a remix.")
        }
        for entry in entries { try validateEntry(entry) }
        if locked.isEmpty, entries.allSatisfy({ $0.fileKind == .fxp }) {
            return try randomizeSerum(entries)
        }
        return try randomizeApp(entries, current: current, locked: locked)
    }

    private static func store(data: Data, kind: PresetFileKind) throws -> LibraryPreset {
        try prepareDirectory()
        let existing = try loadLibrary()
        let fingerprint = sourceFingerprint(data)
        for entry in existing where entry.fileKind == kind && entry.sourceFingerprint == fingerprint {
            if try originalData(entry) == data { return entry }
        }
        guard existing.count < maximumEntries else {
            throw PatchError.invalid("The personal library is full (512 presets).")
        }
        let id = UUID().uuidString
        let filename = "\(id).\(kind.rawValue)"
        let parsed: ParsedPreset
        if kind == .fxp {
            parsed = try readSerum(data, includeAssets: false)
        } else {
            let patch = try JSONDecoder().decode(SoundPatch.self, from: data).validated()
            parsed = ParsedPreset(patch: patch, mapped: patch.parameters, raw: [], warnings: [],
                                  tableFrames: (0..<3).map { oscillator in
                                      patch.wavetables.first { $0.oscillator == oscillator }.map { $0.samples.count / $0.frameSize } ?? 0
                                  }, sampleFrames: (0..<3).map { oscillator in
                                      patch.samples.first { $0.oscillator == oscillator }?.samples.count ?? 0
                                  }, tableNames: ["", "", ""], author: "")
        }
        let entry = LibraryPreset(id: id, name: parsed.patch.name, fileKind: kind,
                                  relativeFilename: filename, parameters: parsed.mapped,
                                  rawParameters: parsed.raw, routes: parsed.patch.routes,
                                  warnings: parsed.warnings, tableFrameCounts: parsed.tableFrames,
                                  sampleFrameCounts: parsed.sampleFrames, tableNames: parsed.tableNames,
                                  author: parsed.author, importedAt: Date(), sourceFingerprint: fingerprint)
        try validateEntry(entry)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let metadata = try encoder.encode(entry)
        guard metadata.count <= maximumMetadataBytes else { throw PatchError.invalid("Preset metadata is too large.") }
        let original = directory.appendingPathComponent(filename)
        do {
            try data.write(to: original, options: .atomic)
            try metadata.write(to: directory.appendingPathComponent("\(id).json"), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: original)
            throw error
        }
        return entry
    }

    private static func randomizeSerum(_ entries: [LibraryPreset]) throws -> PresetRandomization {
        // Older Serum builds have shorter arrays. Using the largest selected
        // schema lets every available stored control participate in the mix.
        let maximumCount = entries.map(\.rawParameters.count).max() ?? 0
        let schemaEntries = entries.filter { $0.rawParameters.count == maximumCount }
        let maximumEmbedded = schemaEntries.map { $0.tableFrameCounts.prefix(2).filter { $0 > 0 }.count }.max() ?? 0
        let templates = schemaEntries.filter { $0.tableFrameCounts.prefix(2).filter { $0 > 0 }.count == maximumEmbedded }
        guard let template = templates.randomElement() else {
            throw PatchError.invalid("Select a supported Serum preset before generating a remix.")
        }
        let original = try originalData(template)
        let mixedData = try withSerum(original) { preset -> Data in
            let count = Int(sd_preset_raw_count(preset))
            guard count > 0, count <= 512 else { throw PatchError.invalid("This Serum preset has an unsupported parameter layout.") }
            var values = [Float]()
            values.reserveCapacity(count)
            for index in 0..<count {
                let donors = entries.filter { $0.rawParameters.count > index }
                guard let donor = donors.randomElement() else { throw PatchError.invalid("The selected presets cannot supply this parameter layout.") }
                values.append(donor.rawParameters[index])
            }
            let required = values.withUnsafeBufferPointer {
                sd_preset_write_fxp(preset, $0.baseAddress, Int32(values.count), nil, 0)
            }
            guard required > 0, Int(required) <= SoundPatch.maximumFileBytes else {
                throw PatchError.invalid("The experimental Serum remix could not be written.")
            }
            var bytes = [UInt8](repeating: 0, count: Int(required))
            let written = values.withUnsafeBufferPointer { raw in
                bytes.withUnsafeMutableBufferPointer { output in
                    sd_preset_write_fxp(preset, raw.baseAddress, Int32(values.count), output.baseAddress, Int32(output.count))
                }
            }
            guard written == required else { throw PatchError.invalid("The experimental Serum remix could not be written completely.") }
            return Data(bytes)
        }
        let preview = try readSerum(mixedData, includeAssets: true)
        var patch = preview.patch
        patch.name = "Remix • \(String(template.name.prefix(65)))"
        let detail = preview.warnings.isEmpty ? "" : " Preview has \(preview.warnings.count) limitations; check the source preset details."
        let muted = (0..<2).filter { oscillator in
            preview.tableFrames[oscillator] == 0 && preview.raw.count > 212 + oscillator && preview.raw[212 + oscillator] >= 0.5
        }.count
        let missingAssets = muted == 0 ? "" : " \(muted) oscillator previews are muted because their wavetables are not embedded."
        return PresetRandomization(patch: try patch.validated(),
                                   summary: "Mixed \(preview.raw.count) stored Serum controls from \(entries.count) presets. Routing and assets come from \(template.name). The phone plays a simplified preview; experimental FXP export needs checking in Serum.\(missingAssets)\(detail)",
                                   fxpData: mixedData)
    }

    private static func randomizeApp(_ entries: [LibraryPreset], current: SoundPatch, locked: Set<Int>) throws -> PresetRandomization {
        var patch = try current.validated()
        var protected = locked
        var retainedAssets = false
        // Mode, table and their assets travel together. A lock on either keeps
        // the current pair and prevents replacing its matching audio data.
        for oscillator in 0..<3 {
            let base = oscillator * 32
            if locked.contains(base) || locked.contains(base + 1) {
                protected.insert(base)
                protected.insert(base + 1)
                continue
            }
            let assetDonors = entries.filter { entry in
                guard let mode = entry.parameters[String(base)] else { return false }
                if entry.fileKind == .fxp { return oscillator < 2 && entry.tableFrameCounts[oscillator] > 0 }
                if mode == 1 || mode == 2 { return entry.sampleFrameCounts[oscillator] > 0 }
                if mode == 3 { return true } // Native spectral mode can use built-in harmonics.
                return true // Native wavetable mode includes its own built-in tables.
            }
            if let donor = assetDonors.randomElement() {
                let source = try loadPatch(donor)
                patch.parameters[String(base)] = source.parameters[String(base)]
                patch.parameters[String(base + 1)] = source.parameters[String(base + 1)]
                patch.samples.removeAll { $0.oscillator == oscillator }
                patch.wavetables.removeAll { $0.oscillator == oscillator }
                if let asset = source.samples.first(where: { $0.oscillator == oscillator }) { patch.samples.append(asset) }
                if let asset = source.wavetables.first(where: { $0.oscillator == oscillator }) { patch.wavetables.append(asset) }
            } else {
                retainedAssets = true
            }
            protected.insert(base)
            protected.insert(base + 1)
        }
        var changed = 0
        for descriptor in ParameterCatalog.descriptors where !protected.contains(descriptor.id) {
            let key = String(descriptor.id)
            let available = entries.compactMap { $0.parameters[key] }
            if let value = available.randomElement() {
                patch.parameters[key] = value
                changed += 1
            }
        }
        // Keep one donor's understood connections together, while protecting
        // locked destinations so a fixed control does not acquire new motion.
        let routeDonors = entries.filter { !$0.routes.isEmpty }
        if let donor = routeDonors.randomElement() {
            let preserved = current.routes.filter { locked.contains($0.destination) }
            let chosen = donor.routes.filter { !locked.contains($0.destination) }
            patch.routes = Array((preserved + chosen).prefix(16)).enumerated().map { index, route in
                .init(slot: index, source: route.source, destination: route.destination, amount: route.amount)
            }
        }
        patch.name = "Remix • Sound pool"
        let assetNote = retainedAssets ? " Current oscillator assets were kept where the selection had no available audio asset." : ""
        let previewNote = entries.contains { $0.isPartialPreview } ? " Serum controls use the app's simplified sound engine." : ""
        return PresetRandomization(patch: try patch.validated(),
                                   summary: "Mixed \(changed) available app controls from \(entries.count) presets. \(locked.count) controls kept fixed. Export this result as an app patch; FXP export is available for an unlocked pool containing only Serum FXPs.\(assetNote)\(previewNote)",
                                   fxpData: nil)
    }

    private struct ParsedPreset {
        let patch: SoundPatch
        let mapped: [String: Float]
        let raw: [Float]
        let warnings: [String]
        let tableFrames: [Int]
        let sampleFrames: [Int]
        let tableNames: [String]
        let author: String
    }

    private static func readSerum(_ data: Data, includeAssets: Bool) throws -> ParsedPreset {
        try withSerum(data) { preset in
            var mapped: [String: Float] = [:]
            for descriptor in ParameterCatalog.descriptors {
                var value: Float = 0
                if sd_preset_mapped_parameter(preset, Int32(descriptor.id), &value) == 1 {
                    mapped[String(descriptor.id)] = value
                }
            }
            var raw: [Float] = []
            let count = Int(sd_preset_raw_count(preset))
            guard (0...512).contains(count) else { throw PatchError.invalid("This preset has an unsupported parameter count.") }
            for index in 0..<count {
                var value: Float = 0
                guard sd_preset_raw_parameter(preset, Int32(index), &value) == 1 else {
                    throw PatchError.invalid("This preset contains an unreadable Serum control.")
                }
                raw.append(value)
            }
            var parameters = ParameterCatalog.defaults
            for (key, value) in mapped { parameters[key] = value }
            var routes: [ModulationRoute] = []
            let routeCount = Int(sd_preset_route_count(preset))
            guard (0...16).contains(routeCount) else { throw PatchError.invalid("This preset contains too many translated connections.") }
            for index in 0..<routeCount {
                var source: Int32 = 0, destination: Int32 = 0
                var amount: Float = 0
                if sd_preset_route(preset, Int32(index), &source, &destination, &amount) == 1 {
                    routes.append(.init(slot: routes.count, source: Int(source), destination: Int(destination), amount: amount))
                }
            }
            var warnings = cString(sd_preset_warnings(preset)).split(separator: "\n").map(String.init)
            var assets: [WavetableAsset] = []
            var tableFrames = [0, 0, 0]
            var tableNames = ["", "", ""]
            for oscillator in 0..<2 {
                var sampleCount: Int32 = 0, frameSize: Int32 = 0
                let samples = sd_preset_oscillator_table(preset, Int32(oscillator), &sampleCount, &frameSize)
                tableNames[oscillator] = cString(sd_preset_oscillator_table_name(preset, Int32(oscillator)))
                if let samples, sampleCount > 0, frameSize == 2_048 {
                    tableFrames[oscillator] = Int(sampleCount / frameSize)
                    if includeAssets {
                        assets.append(.init(oscillator: oscillator, samples: Array(UnsafeBufferPointer(start: samples, count: Int(sampleCount)))))
                    }
                } else {
                    // Missing references are never replaced by a different
                    // factory wavetable in the audible preview.
                    let levelID = oscillator * 32 + 3
                    if parameters[String(levelID), default: 0] > 0 || routes.contains(where: { $0.destination == levelID }) {
                        warnings.append("Oscillator \(["A", "B"][oscillator]) is muted in the preview because its wavetable is not embedded: \(tableNames[oscillator].isEmpty ? "external table" : tableNames[oscillator]).")
                    }
                    parameters[String(levelID)] = 0
                    routes.removeAll { $0.destination / 32 == oscillator && $0.destination < 96 }
                }
            }
            // Serum 1 has no oscillator C. The starter's third oscillator is
            // disabled rather than invented when translating a Serum preset.
            parameters["67"] = 0
            routes = routes.enumerated().map { index, route in
                .init(slot: index, source: route.source, destination: route.destination, amount: route.amount)
            }
            let proposedName = cString(sd_preset_name(preset)).trimmingCharacters(in: .whitespacesAndNewlines)
            let name = proposedName.isEmpty ? "Imported Serum preset" : String(proposedName.prefix(80))
            let patch = try SoundPatch(name: name, parameters: parameters, routes: routes, wavetables: assets).validated()
            // Metadata reflects controls and routes actually available to the
            // preview, including muting missing assets.
            for key in Array(mapped.keys) { mapped[key] = patch.parameters[key] }
            return ParsedPreset(patch: patch, mapped: mapped, raw: raw, warnings: warnings,
                                tableFrames: tableFrames, sampleFrames: [0, 0, 0], tableNames: tableNames,
                                author: cString(sd_preset_author(preset)))
        }
    }

    private static func withSerum<T>(_ data: Data, _ body: (OpaquePointer) throws -> T) throws -> T {
        guard !data.isEmpty, data.count <= SoundPatch.maximumFileBytes else { throw PatchError.invalid("Choose a preset smaller than 32 MB.") }
        var error = [CChar](repeating: 0, count: 512)
        let preset = data.withUnsafeBytes { buffer in
            error.withUnsafeMutableBufferPointer { message in
                sd_preset_parse(buffer.bindMemory(to: UInt8.self).baseAddress, Int32(data.count), message.baseAddress, Int32(message.count))
            }
        }
        guard let preset else {
            let reason = error.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            throw PatchError.invalid(reason.isEmpty ? "This Serum preset could not be read." : reason)
        }
        defer { sd_preset_destroy(preset) }
        return try body(preset)
    }

    private static func cString(_ pointer: UnsafePointer<CChar>?) -> String {
        pointer.map { String(cString: $0) } ?? ""
    }

    private static func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func metadataFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
    }

    private static func originalData(_ entry: LibraryPreset) throws -> Data {
        try validateEntry(entry)
        return try boundedData(directory.appendingPathComponent(entry.relativeFilename), limit: SoundPatch.maximumFileBytes)
    }

    private static func boundedData(_ url: URL, limit: Int) throws -> Data {
        let resource = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard resource.isRegularFile == true, let size = resource.fileSize, size > 0, size <= limit else {
            throw PatchError.invalid(limit == SoundPatch.maximumFileBytes
                                     ? "Choose a nonempty preset file smaller than 32 MB."
                                     : "A personal-library metadata file is empty or too large.")
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= limit else { throw PatchError.invalid("This preset file is too large.") }
        return data
    }

    private static func sourceFingerprint(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }

    private static func validateEntry(_ entry: LibraryPreset) throws {
        guard UUID(uuidString: entry.id) != nil,
              entry.relativeFilename == "\(entry.id).\(entry.fileKind.rawValue)",
              !entry.name.isEmpty, entry.name.count <= 80,
              entry.rawParameters.count <= 512,
              entry.rawParameters.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              entry.tableFrameCounts.count == 3, entry.sampleFrameCounts.count == 3, entry.tableNames.count == 3,
              entry.tableFrameCounts.allSatisfy({ (0...256).contains($0) }),
              entry.sampleFrameCounts.allSatisfy({ (0...480_000).contains($0) }) else {
            throw PatchError.invalid("A personal-library entry is invalid.")
        }
        _ = try SoundPatch(name: entry.name, parameters: entry.parameters, routes: entry.routes).validated()
        if entry.fileKind == .fxp, entry.rawParameters.count < 228 {
            throw PatchError.invalid("A Serum library entry is missing its stored controls.")
        }
    }
}
