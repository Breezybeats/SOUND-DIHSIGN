import Foundation

public struct ParameterDescriptor: Sendable {
    public let id: Int
    public let name: String
    public let range: ClosedRange<Float>
    public let defaultValue: Float
    public let isDiscrete: Bool

    public init(id: Int, name: String, range: ClosedRange<Float>, defaultValue: Float, isDiscrete: Bool = false) {
        self.id = id
        self.name = name
        self.range = range
        self.defaultValue = defaultValue
        self.isDiscrete = isDiscrete
    }
}

public enum ParameterCatalog {
    public static let descriptors: [ParameterDescriptor] = {
        var values: [ParameterDescriptor] = []
        for oscillator in 0..<3 {
            let prefix = "OSC \(["A", "B", "C"][oscillator]) "
            let offset = oscillator * 32
            values += [
                .init(id: offset, name: prefix + "Mode", range: 0...3, defaultValue: 0, isDiscrete: true),
                .init(id: offset + 1, name: prefix + "Table", range: 0...2, defaultValue: Float(oscillator), isDiscrete: true),
                .init(id: offset + 2, name: prefix + "Position", range: 0...1, defaultValue: 0.25),
                .init(id: offset + 3, name: prefix + "Level", range: 0...1, defaultValue: oscillator == 0 ? 0.75 : 0),
                .init(id: offset + 4, name: prefix + "Semitones", range: -24...24, defaultValue: 0),
                .init(id: offset + 5, name: prefix + "Fine", range: -100...100, defaultValue: 0),
                .init(id: offset + 6, name: prefix + "Unison", range: 1...4, defaultValue: 1, isDiscrete: true),
                .init(id: offset + 7, name: prefix + "Detune", range: 0...1, defaultValue: 0.1),
                .init(id: offset + 8, name: prefix + "Pan", range: 0...1, defaultValue: 0.5),
                .init(id: offset + 9, name: prefix + "Warp", range: 0...1, defaultValue: 0),
                .init(id: offset + 10, name: prefix + "Scan", range: 0...1, defaultValue: 0),
                .init(id: offset + 11, name: prefix + "Grain size", range: 0.01...0.25, defaultValue: 0.08),
                .init(id: offset + 12, name: prefix + "Density", range: 1...60, defaultValue: 12),
                .init(id: offset + 13, name: prefix + "Octave", range: -4...4, defaultValue: 0, isDiscrete: true)
            ]
        }
        values += [
            .init(id: 128, name: "Filter cutoff", range: 20...20_000, defaultValue: 12_000),
            .init(id: 129, name: "Resonance", range: 0...1, defaultValue: 0.15),
            .init(id: 130, name: "Drive", range: 0...1, defaultValue: 0.08),
            .init(id: 131, name: "Delay", range: 0...1, defaultValue: 0),
            .init(id: 132, name: "LFO 1 rate", range: 0.05...20, defaultValue: 1),
            .init(id: 133, name: "Master", range: 0...1, defaultValue: 0.65),
            .init(id: 134, name: "Attack", range: 0.001...5, defaultValue: 0.005),
            .init(id: 135, name: "Decay", range: 0.001...5, defaultValue: 0.2),
            .init(id: 136, name: "Sustain", range: 0...1, defaultValue: 0.8),
            .init(id: 137, name: "Release", range: 0.001...5, defaultValue: 0.15),
            .init(id: 138, name: "Sub level", range: 0...1, defaultValue: 0),
            .init(id: 139, name: "Noise level", range: 0...1, defaultValue: 0),
            .init(id: 140, name: "Macro 1", range: 0...1, defaultValue: 0.5)
        ]
        return values
    }()

    public static var defaults: [String: Float] {
        Dictionary(uniqueKeysWithValues: descriptors.map { (String($0.id), $0.defaultValue) })
    }

    public static func descriptor(_ id: Int) -> ParameterDescriptor? { descriptors.first { $0.id == id } }
    public static func name(_ id: Int) -> String { descriptor(id)?.name ?? "Unknown parameter" }
    public static func sourceName(_ id: Int) -> String {
        switch id {
        case 1: return "LFO 1"
        case 2: return "ENV 1"
        case 3: return "Velocity"
        case 4: return "Macro 1"
        default: return "Disabled"
        }
    }
}

public struct ModulationRoute: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { slot }
    public var slot: Int
    public var source: Int
    public var destination: Int
    public var amount: Float
    public init(slot: Int, source: Int, destination: Int, amount: Float) {
        self.slot = slot
        self.source = source
        self.destination = destination
        self.amount = amount
    }
}

public struct SampleAsset: Codable, Equatable, Sendable {
    public var oscillator: Int
    public var sampleRate: Double
    public var samples: [Float]
    public init(oscillator: Int, sampleRate: Double, samples: [Float]) {
        self.oscillator = oscillator
        self.sampleRate = sampleRate
        self.samples = samples
    }
}

public struct WavetableAsset: Codable, Equatable, Sendable {
    public var oscillator: Int
    public var frameSize: Int
    public var samples: [Float]
    public init(oscillator: Int, frameSize: Int = 2_048, samples: [Float]) {
        self.oscillator = oscillator
        self.frameSize = frameSize
        self.samples = samples
    }
}

public enum PatchError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let reason): return reason }
    }
}

/// SOUND/DIHSIGN's open interchange format. This is not a Serum preset format.
public struct SoundPatch: Codable, Equatable, Sendable {
    public static let maximumFileBytes = 32 * 1_024 * 1_024
    public var schemaVersion: Int
    public var name: String
    public var parameters: [String: Float]
    public var routes: [ModulationRoute]
    public var samples: [SampleAsset]
    public var wavetables: [WavetableAsset]

    public init(schemaVersion: Int = 1, name: String, parameters: [String: Float], routes: [ModulationRoute] = [], samples: [SampleAsset] = [], wavetables: [WavetableAsset] = []) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.parameters = parameters
        self.routes = routes
        self.samples = samples
        self.wavetables = wavetables
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, name, parameters, routes, samples, wavetables }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        name = try container.decode(String.self, forKey: .name)
        parameters = try container.decode([String: Float].self, forKey: .parameters)
        routes = try container.decode([ModulationRoute].self, forKey: .routes)
        samples = try container.decode([SampleAsset].self, forKey: .samples)
        wavetables = try container.decodeIfPresent([WavetableAsset].self, forKey: .wavetables) ?? []
    }

    public static var initial: SoundPatch {
        .init(name: "Init • Pocket", parameters: ParameterCatalog.defaults)
    }

    /// Reject malformed input before it reaches the audio engine; add defaults for omitted parameters.
    public func validated() throws -> SoundPatch {
        guard schemaVersion == 1 else { throw PatchError.invalid("This patch uses an unsupported schema version.") }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 80 else { throw PatchError.invalid("Patch name must contain 1–80 characters.") }
        var complete = ParameterCatalog.defaults
        for (key, value) in parameters {
            guard let id = Int(key), key == String(id), let descriptor = ParameterCatalog.descriptor(id), value.isFinite, descriptor.range.contains(value) else {
                throw PatchError.invalid("The patch contains an unknown or out-of-range parameter: \(key).")
            }
            guard !descriptor.isDiscrete || value.rounded() == value else { throw PatchError.invalid("Mode, table, unison, and octave values must be whole numbers.") }
            complete[key] = value
        }
        guard routes.count <= 16 else { throw PatchError.invalid("A patch can contain at most 16 modulation routes.") }
        var slots = Set<Int>()
        for route in routes {
            guard (0..<16).contains(route.slot), slots.insert(route.slot).inserted,
                  (1...4).contains(route.source), route.amount.isFinite, (-1...1).contains(route.amount),
                  let destination = ParameterCatalog.descriptor(route.destination), !destination.isDiscrete else {
                throw PatchError.invalid("The patch contains an invalid modulation route.")
            }
        }
        guard samples.count <= 3 else { throw PatchError.invalid("A patch can contain at most three sample assets.") }
        var sampleOscillators = Set<Int>()
        for asset in samples {
            guard (0..<3).contains(asset.oscillator), sampleOscillators.insert(asset.oscillator).inserted,
                  asset.sampleRate.isFinite, (8_000...96_000).contains(asset.sampleRate),
                  !asset.samples.isEmpty, asset.samples.count <= 480_000,
                  Double(asset.samples.count) / asset.sampleRate <= 10,
                  asset.samples.allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else {
                throw PatchError.invalid("Sample assets must be finite mono audio, at most 10 seconds and 480,000 frames each.")
            }
        }
        guard wavetables.count <= 3 else { throw PatchError.invalid("A patch can contain at most three wavetable assets.") }
        var tableOscillators = Set<Int>()
        for asset in wavetables {
            guard (0..<3).contains(asset.oscillator), tableOscillators.insert(asset.oscillator).inserted,
                  asset.frameSize == 2_048, !asset.samples.isEmpty,
                  asset.samples.count % asset.frameSize == 0, asset.samples.count <= asset.frameSize * 256,
                  asset.samples.allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else {
                throw PatchError.invalid("Wavetables must contain 1–256 frames of 2048 finite mono samples each.")
            }
        }
        var result = self
        result.name = cleanName
        result.parameters = complete
        return result
    }
}
