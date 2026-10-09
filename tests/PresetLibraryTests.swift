import Foundation
import SoundCore
#if os(Linux)
import Glibc
#else
import Darwin
#endif

private var assertions = 0
private var failures = 0
private var scenarios = 0

private func check(_ value: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    if !value() { failures += 1; print("FAIL: \(message)") }
}

private func scenario(_ name: String) {
    scenarios += 1
    print("CHECK \(name)")
}

private func expectThrow(_ message: String, _ body: () throws -> Void) {
    do { try body(); check(false, message) } catch { check(true, message) }
}

private func fixtureFiles(_ arguments: [String]) -> [URL] {
    var result: [URL] = []
    for argument in arguments {
        let url = URL(fileURLWithPath: argument)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            while let item = enumerator?.nextObject() as? URL {
                if item.pathExtension.lowercased() == "fxp" { result.append(item) }
            }
        } else { result.append(url) }
    }
    return result.sorted { $0.path < $1.path }
}

private func rawParameters(_ data: Data) throws -> [Float] {
    var error = [CChar](repeating: 0, count: 256)
    let preset = data.withUnsafeBytes { bytes in
        error.withUnsafeMutableBufferPointer {
            sd_preset_parse(bytes.bindMemory(to: UInt8.self).baseAddress, Int32(data.count), $0.baseAddress, Int32($0.count))
        }
    }
    guard let preset else { throw PatchError.invalid("Test FXP could not be parsed.") }
    defer { sd_preset_destroy(preset) }
    let count = Int(sd_preset_raw_count(preset))
    var values = [Float](repeating: 0, count: count)
    for index in values.indices {
        guard sd_preset_raw_parameter(preset, Int32(index), &values[index]) == 1 else {
            throw PatchError.invalid("Test raw parameter could not be read.")
        }
    }
    return values
}

private func appDonor(_ name: String, fraction: Float, samples: Bool) throws -> SoundPatch {
    var values = ParameterCatalog.defaults
    for descriptor in ParameterCatalog.descriptors {
        let value = descriptor.range.lowerBound + fraction * (descriptor.range.upperBound - descriptor.range.lowerBound)
        values[String(descriptor.id)] = descriptor.isDiscrete ? value.rounded() : value
    }
    var sampleAssets: [SampleAsset] = []
    var tableAssets: [WavetableAsset] = []
    for oscillator in 0..<3 {
        let base = oscillator * 32
        values[String(base)] = samples ? 1 : 0
        values[String(base + 1)] = samples ? 2 : 1
        if samples {
            sampleAssets.append(.init(oscillator: oscillator, sampleRate: 24_000, samples: [fraction, -fraction, 0]))
        } else {
            tableAssets.append(.init(oscillator: oscillator, samples: [Float](repeating: fraction, count: 2_048)))
        }
    }
    let routes: [ModulationRoute] = samples
        ? [.init(slot: 0, source: 4, destination: 128, amount: 0.2)]
        : [.init(slot: 0, source: 1, destination: 3, amount: 0.7)]
    return try SoundPatch(name: name, parameters: values, routes: routes, samples: sampleAssets, wavetables: tableAssets).validated()
}

private func run(_ fixtureURLs: [URL], directory: URL) throws {
    scenario("App patch persistence keeps source assets out of metadata")
    let donorA = try appDonor("Original test donor A", fraction: 0.25, samples: false)
    let donorB = try appDonor("Original test donor B", fraction: 0.75, samples: true)
    let entryA = try PresetLibraryStore.savePatch(donorA)
    let entryB = try PresetLibraryStore.savePatch(donorB)
    check(entryA.fileKind == .sdpatch && entryA.rawParameters.isEmpty, "App patch is classified without invented Serum controls")
    check(entryA.tableFrameCounts == [1, 1, 1] && entryB.sampleFrameCounts == [3, 3, 3], "Only asset dimensions enter the metadata")
    let metadataA = try Data(contentsOf: directory.appendingPathComponent("\(entryA.id).json"))
    let objectA = try JSONSerialization.jsonObject(with: metadataA) as? [String: Any]
    check(objectA?["samples"] == nil && objectA?["wavetables"] == nil, "Metadata does not copy audio samples")
    check(metadataA.count < 256 * 1_024, "Metadata stays within its bounded file size")
    let loadedA = try PresetLibraryStore.loadPatch(entryA)
    check(loadedA.parameters == donorA.parameters && loadedA.wavetables == donorA.wavetables, "Stored app patch roundtrips with original assets")
    let savedAgain = try PresetLibraryStore.savePatch(donorA)
    check(savedAgain.id == entryA.id, "Repeated identical app imports deduplicate")
    var reloaded = try PresetLibraryStore.loadLibrary()
    check(Set(reloaded.map(\.id)) == Set([entryA.id, entryB.id]), "Persistent metadata reloads both entries")

    scenario("Locked values, oscillator mode/table assets and destination connections stay fixed")
    var current = donorA
    current.name = "Current locked patch"
    current.parameters["3"] = 0.123
    current.parameters["1"] = 2
    current.wavetables[0] = .init(oscillator: 0, samples: [Float](repeating: -0.15, count: 2_048))
    current.routes = [.init(slot: 0, source: 2, destination: 3, amount: 0.27)]
    for _ in 0..<8 {
        let remix = try PresetLibraryStore.randomize(entries: [entryA, entryB], current: current, locked: [0, 3])
        check(remix.fxpData == nil, "Locked or native remix does not claim a full Serum export")
        check(remix.patch.parameters["3"] == 0.123, "Locked level is unchanged")
        check(remix.patch.parameters["0"] == current.parameters["0"] && remix.patch.parameters["1"] == 2, "Locking mode also keeps the matching table selection")
        check(remix.patch.wavetables.first(where: { $0.oscillator == 0 }) == current.wavetables.first(where: { $0.oscillator == 0 }), "Locked mode retains its table data")
        check(remix.patch.routes.contains(where: { $0.destination == 3 && $0.source == 2 && $0.amount == 0.27 }), "Locked destination retains its original connection")
        check(!remix.patch.routes.contains(where: { $0.destination == 3 && $0.source != 2 }), "Donor routes cannot replace a locked destination")
        for descriptor in ParameterCatalog.descriptors where descriptor.id != 0 && descriptor.id != 1 && descriptor.id != 3 {
            let value = remix.patch.parameters[String(descriptor.id)]
            let values = [entryA.parameters[String(descriptor.id)], entryB.parameters[String(descriptor.id)]]
            check(values.contains(value), "Randomized controls use values from the selected donors")
        }
        for oscillator in 1..<3 {
            let mode = remix.patch.parameters[String(oscillator * 32)]
            if mode == 1 {
                check(remix.patch.samples.first(where: { $0.oscillator == oscillator }) == donorB.samples.first(where: { $0.oscillator == oscillator }), "Sample mode travels with its donor's sample")
                check(!remix.patch.wavetables.contains(where: { $0.oscillator == oscillator }), "Sample donor clears the prior wavetable")
            } else {
                check(remix.patch.wavetables.first(where: { $0.oscillator == oscillator }) == donorA.wavetables.first(where: { $0.oscillator == oscillator }), "Wavetable mode travels with its donor's table")
                check(!remix.patch.samples.contains(where: { $0.oscillator == oscillator }), "Wavetable donor clears the prior sample")
            }
        }
    }

    scenario("Invalid source files and malformed persistent metadata fail before use")
    let invalidURL = directory.appendingPathComponent("test-invalid.sdpatch")
    try Data("{\"schemaVersion\":999}".utf8).write(to: invalidURL)
    expectThrow("Invalid app patch is rejected") { _ = try PresetLibraryStore.importFile(invalidURL) }
    let unsupportedURL = directory.appendingPathComponent("test-invalid.wav")
    try Data([1, 2, 3]).write(to: unsupportedURL)
    expectThrow("Unsupported source extension is rejected") { _ = try PresetLibraryStore.importFile(unsupportedURL) }
    expectThrow("Empty donor selection is rejected") { _ = try PresetLibraryStore.randomize(entries: [], current: current, locked: []) }
    let metadataURL = directory.appendingPathComponent("\(entryA.id).json")
    var modified = objectA ?? [:]
    modified["relativeFilename"] = "../outside.sdpatch"
    try JSONSerialization.data(withJSONObject: modified).write(to: metadataURL)
    expectThrow("Metadata cannot redirect original-file access outside its directory") { _ = try PresetLibraryStore.loadLibrary() }
    try metadataA.write(to: metadataURL)

    var serumEntries: [LibraryPreset] = []
    if !fixtureURLs.isEmpty {
        scenario("Uploaded FXPs import as bounded asset-free metadata with byte-identical private originals")
        for url in fixtureURLs {
            let entry = try PresetLibraryStore.importFile(url)
            serumEntries.append(entry)
            check(entry.fileKind == .fxp && [260, 273, 299].contains(entry.rawParameters.count), "Imported Serum schema has its verified normalized knob count")
            check(!entry.warnings.isEmpty && entry.isPartialPreview, "Preview limitations remain explicit in library metadata")
            let original = try Data(contentsOf: url)
            let privateCopy = try Data(contentsOf: directory.appendingPathComponent(entry.relativeFilename))
            check(original == privateCopy, "The imported source is stored byte-for-byte unchanged")
            let metadata = try Data(contentsOf: directory.appendingPathComponent("\(entry.id).json"))
            let object = try JSONSerialization.jsonObject(with: metadata) as? [String: Any]
            check(metadata.count < 256 * 1_024 && object?["samples"] == nil && object?["wavetables"] == nil,
                  "FXP metadata stores scalar values and dimensions without embedded audio arrays")
            check(entry.parameters["67"] == 0, "Serum 1 does not invent a third audible oscillator")
            for oscillator in 0..<2 where entry.tableFrameCounts[oscillator] == 0 {
                check(entry.parameters[String(oscillator * 32 + 3)] == 0, "A missing table keeps its preview oscillator muted")
                check(!entry.routes.contains(where: { $0.destination < 96 && $0.destination / 32 == oscillator }), "Modulation cannot revive a missing table with a different built-in sound")
            }
        }
        print("Swift private fixtures checked: \(fixtureURLs.count)")
        reloaded = try PresetLibraryStore.loadLibrary()
        check(reloaded.count <= PresetLibraryStore.maximumEntries, "The uploaded selection fits the 512-entry library")
        check(Set(serumEntries.map(\.id)).isSubset(of: Set(reloaded.map(\.id))), "FXP metadata survives persistent reload")
        let deduplicated = try PresetLibraryStore.importFile(fixtureURLs[0])
        check(deduplicated.id == serumEntries[0].id, "Repeated identical FXP imports deduplicate without replacing source data")

        scenario("FXP remix chooses every raw parameter from selected donors and previews the actual exported bytes")
        var selected: [LibraryPreset] = []
        for count in [260, 273, 299] {
            if let entry = serumEntries.first(where: { $0.rawParameters.count == count }) { selected.append(entry) }
        }
        let maximumCount = selected.map(\.rawParameters.count).max() ?? 0
        for _ in 0..<4 {
            let remix = try PresetLibraryStore.randomize(entries: selected, current: current, locked: [])
            guard let data = remix.fxpData else { throw PatchError.invalid("Test FXP remix did not produce export data.") }
            let raw = try rawParameters(data)
            check(raw.count == maximumCount, "The highest selected schema supplies the export template")
            for index in raw.indices {
                let candidates = selected.compactMap { index < $0.rawParameters.count ? $0.rawParameters[index] : nil }
                check(candidates.contains(raw[index]), "Each exported Serum parameter belongs to its selected donor column")
            }
            let generatedURL = directory.appendingPathComponent("test-remix.fxp")
            try data.write(to: generatedURL)
            let generated = try PresetLibraryStore.importFile(generatedURL)
            let preview = try PresetLibraryStore.loadPatch(generated)
            check(preview.parameters == remix.patch.parameters && preview.routes == remix.patch.routes && preview.wavetables == remix.patch.wavetables,
                  "Audition values and assets match a re-import of the actual generated FXP")
            check(preview.parameters["67"] == 0, "Remixed Serum preview keeps the third oscillator silent")
            let nativeFallback = try PresetLibraryStore.randomize(entries: selected, current: current, locked: [3])
            check(nativeFallback.fxpData == nil && nativeFallback.patch.parameters["3"] == current.parameters["3"], "A locked Serum pool falls back to a truthful native patch remix")
        }
    }

    scenario("Library entry limits fail before reading an oversized index")
    let count = try PresetLibraryStore.loadLibrary().count
    var extraURLs: [URL] = []
    for _ in count...PresetLibraryStore.maximumEntries {
        let url = directory.appendingPathComponent("\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: url)
        extraURLs.append(url)
    }
    expectThrow("More than 512 metadata entries are rejected") { _ = try PresetLibraryStore.loadLibrary() }
    for url in extraURLs { try FileManager.default.removeItem(at: url) }

    scenario("Deleting an import removes only the private library copy")
    if let entry = serumEntries.first, let sourceURL = fixtureURLs.first {
        let source = try Data(contentsOf: sourceURL)
        try PresetLibraryStore.remove(entry)
        check(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(entry.relativeFilename).path), "Private source copy is removed")
        check(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(entry.id).json").path), "Private metadata is removed")
        let remainingSource = try Data(contentsOf: sourceURL)
        check(source == remainingSource, "The user's uploaded source remains unchanged")
    } else {
        try PresetLibraryStore.remove(entryA)
        check(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(entryA.relativeFilename).path), "Native private library copy is removed")
    }
}

@main
struct PresetLibraryTests {
    static func main() {
        guard let path = ProcessInfo.processInfo.environment["SOUND_DIHSIGN_TEST_LIBRARY_PATH"], path.hasPrefix("/tmp/") else {
            print("Tests require a unique SOUND_DIHSIGN_TEST_LIBRARY_PATH below /tmp.")
            exit(1)
        }
        do { try run(fixtureFiles(Array(CommandLine.arguments.dropFirst())), directory: URL(fileURLWithPath: path, isDirectory: true)) }
        catch { failures += 1; print("UNEXPECTED: \(error)") }
        print("Preset library tests: \(scenarios) scenarios, \(assertions) assertions, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
