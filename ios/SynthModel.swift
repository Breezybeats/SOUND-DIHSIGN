import SwiftUI
import AVFoundation
import SoundCore

enum SynthPage: String, CaseIterable { case oscillator, filter, envelopes, effects, modulation }

@MainActor
final class SynthModel: ObservableObject {
    @Published var patch = SoundPatch.initial
    @Published var selectedOscillator = 0
    @Published var octave = 3
    @Published var selectedPage: SynthPage = .oscillator
    @Published var status = "Ready to make a sound"
    @Published var audioReady = false
    @Published var sampleImportOscillator: Int?
    @Published var isImportingSample = false
    @Published var wavetableImportOscillator: Int?
    @Published var isImportingWavetable = false
    @Published var isImportingPatch = false
    @Published var isExportingPatch = false {
        didSet { if isExportingPatch { exportDocument = PatchDocument(patch: patch) } }
    }
    @Published var exportDocument = PatchDocument()
    @Published var selectedSource = 1
    @Published var generatingOscillator: Int?
    @Published var generatedWavetableNames: [Int: String] = [:]

    private var audio = AudioController()
    private var activeNotes: [Int: Float] = [:]
    private var observers: [NSObjectProtocol] = []
    private var resumeAfterInterruption = false
    private var generationID: UUID?
    private var patchRevision: UInt64 = 0
    private var generatedCounts: [Int: Int] = [:]

    init() {
        do { try audio.prepare(patch) } catch { status = error.localizedDescription }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let typeRaw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.allNotesOff()
                if reasonRaw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                    self.stopAudio()
                    self.status = "Audio output disconnected. Tap play to resume."
                } else if self.audioReady {
                    self.startAudio()
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stopAudio()
                self.audio = AudioController()
                do {
                    try self.audio.prepare(self.patch)
                    self.status = "Audio system reset. Tap play to resume."
                } catch { self.status = error.localizedDescription }
            }
        })
    }

    func value(_ id: Int) -> Float { patch.parameters[String(id)] ?? ParameterCatalog.descriptor(id)?.defaultValue ?? 0 }

    func set(_ id: Int, _ newValue: Float) {
        guard let descriptor = ParameterCatalog.descriptor(id), newValue.isFinite else { return }
        var clean = min(descriptor.range.upperBound, max(descriptor.range.lowerBound, newValue))
        if descriptor.isDiscrete { clean = clean.rounded() }
        if let oscillator = generatingOscillator, (id == oscillator * 32 || id == oscillator * 32 + 1) {
            invalidateGeneration()
            status = "Wavetable generation canceled."
        }
        patch.parameters[String(id)] = clean
        audio.setParameter(id, clean)
    }

    func transposeOctave(for oscillator: Int, by octaves: Int) {
        guard (0..<3).contains(oscillator), (-1...1).contains(octaves) else { return }
        let id = oscillator * 32 + 13
        set(id, value(id) + Float(octaves))
    }

    /// Generates original harmonic frames off the main thread, then replaces only
    /// this oscillator's wavetable. Pitch, levels, envelopes and routes are kept.
    func generateWavetable(for oscillator: Int) {
        guard (0..<3).contains(oscillator), generatingOscillator == nil else { return }
        let id = UUID()
        let revision = patchRevision
        let seed = UInt32.random(in: UInt32.min...UInt32.max)
        generationID = id
        generatingOscillator = oscillator
        status = "Creating a new wavetable…"

        Task { [weak self] in
            let samples: [Float]? = await Task.detached(priority: .userInitiated) {
                var samples = [Float](repeating: 0, count: 2_048 * 16)
                let success = samples.withUnsafeMutableBufferPointer { buffer in
                    sd_generate_wavetable(buffer.baseAddress, Int32(buffer.count), 2_048, seed)
                }
                return success == 1 ? samples : nil
            }.value
            guard let self, self.generationID == id else { return }
            defer {
                if self.generationID == id { self.invalidateGeneration() }
            }
            guard self.patchRevision == revision else { return }
            guard let samples else {
                self.status = "The wavetable could not be generated. Try again."
                return
            }
            do {
                var next = self.patch
                next.wavetables.removeAll { $0.oscillator == oscillator }
                next.wavetables.append(.init(oscillator: oscillator, samples: samples))
                next.parameters[String(oscillator * 32)] = 0
                try self.replacePatch(next.validated(), resumeHeldNotes: true)
                let count = self.generatedCounts[oscillator, default: 0] + 1
                self.generatedCounts[oscillator] = count
                self.generatedWavetableNames[oscillator] = "Generated \(count)"
                self.status = "New wavetable ready in oscillator \(["A", "B", "C"][oscillator])."
            } catch {
                self.status = "Generation failed: \(error.localizedDescription)"
            }
        }
    }

    private func invalidateGeneration() {
        generationID = nil
        generatingOscillator = nil
    }

    func noteOn(_ note: Int, velocity: Float = 0.8) {
        guard (0...127).contains(note), velocity.isFinite else { return }
        if !audioReady { startAudio() }
        guard audioReady, activeNotes[note] == nil else { return }
        let cleanVelocity = min(1, max(0.01, velocity))
        activeNotes[note] = cleanVelocity
        audio.noteOn(note, cleanVelocity)
    }

    func noteOff(_ note: Int) {
        guard activeNotes.removeValue(forKey: note) != nil else { return }
        audio.noteOff(note)
    }

    func allNotesOff() { activeNotes.removeAll(); audio.allNotesOff() }

    func startAudio() {
        do { try audio.start(); audioReady = true; status = "Audio on • 8 voices" }
        catch { audioReady = false; status = "Audio unavailable: \(error.localizedDescription)" }
    }

    func stopAudio() { allNotesOff(); audio.stop(); audioReady = false }

    func route(source: Int, destination: Int, amount: Float = 0.4) {
        guard amount.isFinite, (1...4).contains(source), let descriptor = ParameterCatalog.descriptor(destination), !descriptor.isDiscrete else {
            status = "Choose a continuous control for modulation."
            return
        }
        if let existing = patch.routes.first(where: { $0.source == source && $0.destination == destination }) {
            selectedPage = .modulation
            status = "\(ParameterCatalog.sourceName(source)) already controls \(descriptor.name), slot \(existing.slot + 1)."
            return
        }
        guard let slot = (0..<16).first(where: { slot in !patch.routes.contains { $0.slot == slot } }) else {
            status = "All 16 modulation slots are in use. Remove a route to add another."
            return
        }
        let route = ModulationRoute(slot: slot, source: source, destination: destination, amount: min(1, max(-1, amount)))
        patch.routes.append(route)
        audio.setRoute(route)
        status = "\(ParameterCatalog.sourceName(source)) → \(descriptor.name)"
    }

    func setRouteAmount(slot: Int, amount: Float) {
        guard amount.isFinite, let index = patch.routes.firstIndex(where: { $0.slot == slot }) else { return }
        patch.routes[index].amount = min(1, max(-1, amount))
        audio.setRoute(patch.routes[index])
    }

    func removeRoute(slot: Int) {
        patch.routes.removeAll { $0.slot == slot }
        audio.clearRoute(slot)
    }

    func loadPatch(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let resource = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = resource.fileSize, size <= SoundPatch.maximumFileBytes else { throw PatchError.invalid("Choose a patch smaller than 32 MB.") }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= SoundPatch.maximumFileBytes else { throw PatchError.invalid("Choose a patch smaller than 32 MB.") }
            let imported = try JSONDecoder().decode(SoundPatch.self, from: data).validated()
            try replacePatch(imported)
            generatedWavetableNames.removeAll()
            status = "Loaded \(imported.name)"
        } catch { status = "Import failed: \(error.localizedDescription)" }
    }

    private func replacePatch(_ next: SoundPatch, resumeHeldNotes: Bool = false) throws {
        let wasRunning = audio.isRunning
        let heldNotes: [Int: Float] = resumeHeldNotes ? activeNotes : [:]
        allNotesOff()
        try audio.prepare(next)
        patch = next
        patchRevision &+= 1
        invalidateGeneration()
        audioReady = false
        if wasRunning { startAudio() }
        if audioReady {
            for (note, velocity) in heldNotes { noteOn(note, velocity: velocity) }
        }
    }

    func importSample(from url: URL) {
        guard let oscillator = sampleImportOscillator, (0..<3).contains(oscillator) else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let format = file.processingFormat
            let rate = format.sampleRate
            guard rate.isFinite, (8_000...192_000).contains(rate), (1...8).contains(Int(format.channelCount)),
                  file.length > 0, Double(file.length) / rate <= 10 else {
                throw PatchError.invalid("Choose an audio file of up to 10 seconds, with 1–8 channels at 8–192 kHz.")
            }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
                throw PatchError.invalid("Could not allocate the sample buffer.")
            }
            try file.read(into: buffer)
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { throw PatchError.invalid("This audio file could not be decoded.") }
            let inputCount = Int(buffer.frameLength)
            let channelCount = Int(format.channelCount)
            var mono = [Float](repeating: 0, count: inputCount)
            for frame in 0..<inputCount {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    let value = channels[channel][frame]
                    sum += value.isFinite ? value : 0
                }
                mono[frame] = min(1, max(-1, sum / Float(channelCount)))
            }
            guard let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
                  let targetFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1),
                  let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(inputCount)),
                  let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(min(480_000, Int(ceil(Double(inputCount) * 48_000 / rate))))),
                  let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                throw PatchError.invalid("Could not prepare the sample-rate converter.")
            }
            source.frameLength = AVAudioFrameCount(inputCount)
            mono.withUnsafeBufferPointer { values in source.floatChannelData![0].update(from: values.baseAddress!, count: inputCount) }
            var provided = false
            var conversionError: NSError?
            let converted = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                if provided { inputStatus.pointee = .endOfStream; return nil }
                provided = true
                inputStatus.pointee = .haveData
                return source
            }
            guard converted != .error, conversionError == nil, output.frameLength > 0, let data = output.floatChannelData else {
                if let conversionError { throw conversionError }
                throw PatchError.invalid("Sample-rate conversion failed.")
            }
            let values = Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength))).map { min(1, max(-1, $0.isFinite ? $0 : 0)) }
            var next = patch
            next.samples.removeAll { $0.oscillator == oscillator }
            next.samples.append(.init(oscillator: oscillator, sampleRate: 48_000, samples: values))
            // Explicit audio import selects audio over custom-table harmonics in spectral mode.
            if value(oscillator * 32) == 3 { next.wavetables.removeAll { $0.oscillator == oscillator } }
            if value(oscillator * 32) == 0 { next.parameters[String(oscillator * 32)] = 1 }
            try replacePatch(next.validated())
            if value(oscillator * 32) == 3 { generatedWavetableNames.removeValue(forKey: oscillator) }
            status = "Loaded \(url.lastPathComponent) into OSC \(["A", "B", "C"][oscillator])"
        } catch { status = "Sample import failed: \(error.localizedDescription)" }
    }

    func resetPatch() {
        do {
            try replacePatch(.initial)
            generatedWavetableNames.removeAll()
            status = "New patch ready"
        }
        catch { status = error.localizedDescription }
    }

    func selectTable(_ table: Int, oscillator: Int) {
        guard (0..<3).contains(oscillator), (0..<3).contains(table) else { return }
        if patch.wavetables.contains(where: { $0.oscillator == oscillator }) {
            var next = patch
            next.wavetables.removeAll { $0.oscillator == oscillator }
            next.parameters[String(oscillator * 32 + 1)] = Float(table)
            do { try replacePatch(next) }
            catch { status = error.localizedDescription; return }
        } else { set(oscillator * 32 + 1, Float(table)) }
        generatedWavetableNames.removeValue(forKey: oscillator)
        status = "Selected \(["Basic", "Growl", "Hollow"][table]) in oscillator \(["A", "B", "C"][oscillator])."
    }

    func importWavetable(from url: URL) {
        guard let oscillator = wavetableImportOscillator, (0..<3).contains(oscillator) else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            guard url.pathExtension.lowercased() == "wav" else { throw PatchError.invalid("Choose a mono .wav wavetable with 2048 samples per frame.") }
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard file.processingFormat.channelCount == 1, file.length > 0,
                  file.length % 2_048 == 0, file.length <= 2_048 * 256 else {
                throw PatchError.invalid("Wavetable WAVs need 1–256 mono frames of 2048 samples. Audio one-shots use Import sample.")
            }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
                throw PatchError.invalid("Could not allocate the wavetable buffer.")
            }
            try file.read(into: buffer)
            guard buffer.frameLength == AVAudioFrameCount(file.length), let data = buffer.floatChannelData else {
                throw PatchError.invalid("The wavetable could not be decoded completely.")
            }
            let samples = Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
            guard samples.allSatisfy({ $0.isFinite && (-1...1).contains($0) }) else {
                throw PatchError.invalid("The wavetable contains invalid or out-of-range audio samples.")
            }
            var next = patch
            next.wavetables.removeAll { $0.oscillator == oscillator }
            next.wavetables.append(.init(oscillator: oscillator, samples: samples))
            next.parameters[String(oscillator * 32)] = 0
            try replacePatch(next.validated())
            generatedWavetableNames.removeValue(forKey: oscillator)
            status = "Imported \(file.length / 2_048)-frame table • \(url.lastPathComponent)"
        } catch { status = "Wavetable import failed: \(error.localizedDescription)" }
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt) {
        if typeRaw == AVAudioSession.InterruptionType.began.rawValue {
            resumeAfterInterruption = audioReady
            stopAudio()
            status = "Audio interrupted"
        } else if typeRaw == AVAudioSession.InterruptionType.ended.rawValue {
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
            if shouldResume && resumeAfterInterruption { startAudio() }
            resumeAfterInterruption = false
        }
    }

    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
}
