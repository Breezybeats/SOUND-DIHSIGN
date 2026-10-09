import AVFoundation
import SoundCore

/// Main-thread controls feed the core's atomic controls and single-producer note queue.
/// The render closure captures only the C engine pointer; it never reads SwiftUI state.
@MainActor
final class AudioController {
    private let audioEngine = AVAudioEngine()
    private var core: OpaquePointer?
    private var sourceNode: AVAudioSourceNode?
    private let sampleRate: Double = 48_000

    var isRunning: Bool { audioEngine.isRunning }

    func prepare(_ patch: SoundPatch) throws {
        let patch = try patch.validated()
        guard let nextCore = sd_create(sampleRate) else { throw PatchError.invalid("The audio engine could not allocate its buffers.") }
        do {
            for asset in patch.samples {
                let loaded = asset.samples.withUnsafeBufferPointer { samples in
                    sd_load_sample(nextCore, Int32(asset.oscillator), samples.baseAddress, Int32(samples.count), asset.sampleRate)
                }
                guard loaded == 1 else { throw PatchError.invalid("The audio engine could not load a sample.") }
            }
            for asset in patch.wavetables {
                let loaded = asset.samples.withUnsafeBufferPointer { samples in
                    sd_load_wavetable(nextCore, Int32(asset.oscillator), samples.baseAddress, Int32(samples.count), Int32(asset.frameSize))
                }
                guard loaded == 1 else { throw PatchError.invalid("The audio engine could not load a wavetable.") }
            }
        } catch {
            sd_destroy(nextCore)
            throw error
        }
        for (id, value) in patch.parameters { sd_set_parameter(nextCore, Int32(id)!, value) }
        for route in patch.routes {
            sd_set_modulation(nextCore, Int32(route.slot), Int32(route.source), Int32(route.destination), route.amount)
        }

        audioEngine.stop()
        if let oldSource = sourceNode { audioEngine.detach(oldSource) }
        if let oldCore = core { sd_destroy(oldCore) }
        core = nextCore
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, list in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard buffers.count == 2,
                  buffers[0].mNumberChannels == 1, buffers[1].mNumberChannels == 1,
                  buffers[0].mDataByteSize >= frameCount * UInt32(MemoryLayout<Float>.size),
                  buffers[1].mDataByteSize >= frameCount * UInt32(MemoryLayout<Float>.size),
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else {
                for buffer in buffers {
                    if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
                }
                return noErr
            }
            sd_render(nextCore, left, right, Int32(frameCount))
            return noErr
        }
        sourceNode = source
        audioEngine.attach(source)
        audioEngine.connect(source, to: audioEngine.mainMixerNode, format: format)
        audioEngine.prepare()
    }

    func start() throws {
        guard core != nil else { throw PatchError.invalid("The audio engine is not initialized.") }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setPreferredSampleRate(sampleRate)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        if !audioEngine.isRunning { try audioEngine.start() }
    }

    func stop() {
        if let core { sd_all_notes_off(core) }
        audioEngine.stop()
    }

    func setParameter(_ id: Int, _ value: Float) { if let core { sd_set_parameter(core, Int32(id), value) } }
    func noteOn(_ note: Int, _ velocity: Float) { if let core { sd_note_on(core, Int32(note), velocity) } }
    func noteOff(_ note: Int) { if let core { sd_note_off(core, Int32(note)) } }
    func allNotesOff() { if let core { sd_all_notes_off(core) } }
    func setRoute(_ route: ModulationRoute) {
        if let core { sd_set_modulation(core, Int32(route.slot), Int32(route.source), Int32(route.destination), route.amount) }
    }
    func clearRoute(_ slot: Int) { if let core { sd_set_modulation(core, Int32(slot), 0, 0, 0) } }

    deinit {
        audioEngine.stop()
        if let sourceNode { audioEngine.detach(sourceNode) }
        if let core { sd_destroy(core) }
    }
}
