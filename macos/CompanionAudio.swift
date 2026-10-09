import AVFoundation
import Foundation
import SoundCore

/// Owns the C engine for as long as an audio callback can reference it.
private final class CompanionCore: @unchecked Sendable {
    let pointer: OpaquePointer

    init(patch: SoundPatch, sampleRate: Double) throws {
        guard let pointer = sd_create(sampleRate) else {
            throw CompanionError.message("Could not allocate the audio engine.")
        }
        self.pointer = pointer
        for (key, value) in patch.parameters {
            if let parameter = Int32(key) { sd_set_parameter(pointer, parameter, value) }
        }
        for sample in patch.samples {
            let loaded = sample.samples.withUnsafeBufferPointer { buffer in
                sd_load_sample(pointer, Int32(sample.oscillator), buffer.baseAddress,
                               Int32(buffer.count), Double(sample.sampleRate))
            }
            guard loaded != 0 else {
                throw CompanionError.message("The audio engine could not load oscillator \(sample.oscillator + 1)'s sample.")
            }
        }
        for table in patch.wavetables {
            let loaded = table.samples.withUnsafeBufferPointer { buffer in
                sd_load_wavetable(pointer, Int32(table.oscillator), buffer.baseAddress,
                                  Int32(buffer.count), Int32(table.frameSize))
            }
            guard loaded != 0 else {
                throw CompanionError.message("The audio engine could not load oscillator \(table.oscillator + 1)'s wavetable.")
            }
        }
        for route in patch.routes {
            sd_set_modulation(pointer, Int32(route.slot), Int32(route.source),
                              Int32(route.destination), route.amount)
        }
    }

    deinit { sd_destroy(pointer) }
}

/// Control operations run on the main thread. The render closure captures only
/// its C-engine owner; it does not access the view model or any main-actor state.
final class CompanionAudioPreview {
    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var core: CompanionCore?

    func start(patch: SoundPatch, note: Int) throws {
        stop()
        let audioEngine = AVAudioEngine()
        let outputRate = audioEngine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = outputRate > 0 ? outputRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw CompanionError.message("The audio output format is unavailable.")
        }
        let core = try CompanionCore(patch: patch, sampleRate: sampleRate)
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let bytes = Int(frameCount) * MemoryLayout<Float>.size
            guard buffers.count == 2,
                  Int(buffers[0].mDataByteSize) >= bytes,
                  Int(buffers[1].mDataByteSize) >= bytes,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else {
                for buffer in buffers {
                    buffer.mData?.initializeMemory(as: UInt8.self, repeating: 0,
                                                   count: Int(buffer.mDataByteSize))
                }
                return noErr
            }
            sd_render(core.pointer, left, right, Int32(frameCount))
            return noErr
        }
        audioEngine.attach(source)
        audioEngine.connect(source, to: audioEngine.mainMixerNode, format: format)
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            audioEngine.detach(source)
            throw error
        }
        self.core = core
        self.sourceNode = source
        self.audioEngine = audioEngine
        sd_note_on(core.pointer, Int32(note), 0.8)
    }

    func stop() {
        if let core { sd_all_notes_off(core.pointer) }
        audioEngine?.stop()
        if let sourceNode { audioEngine?.detach(sourceNode) }
        sourceNode = nil
        audioEngine = nil
        core = nil
    }

    deinit { stop() }
}

enum CompanionWaveRenderer {
    /// Renders a note through the shared synth and its effects, then includes a
    /// release/delay tail. This is flattened stereo PCM audio, not a synth preset.
    static func render(patch: SoundPatch, note: Int, holdSeconds: Double) throws -> URL {
        let sampleRate = 48_000.0
        let core = try CompanionCore(patch: patch, sampleRate: sampleRate)
        let holdFrames = Int(min(max(holdSeconds, 0.25), 8) * sampleRate)
        let hasReleaseModulation = patch.routes.contains { $0.destination == 137 && $0.amount != 0 }
        let release = hasReleaseModulation ? 5 : Double(patch.parameters["137"] ?? 0.4)
        let tailSeconds = min(max(release + 2, 2.5), 7)
        let totalFrames = holdFrames + Int(tailSeconds * sampleRate)
        let fadeFrames = Int(sampleRate * 0.05)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(CompanionStore.filename(patch.name))_\(UUID().uuidString.prefix(8)).wav")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CompanionError.message("Could not create the rendered audio file.")
        }
        let file = try FileHandle(forWritingTo: url)
        do {
            try file.write(contentsOf: waveHeader(frameCount: totalFrames, sampleRate: 48_000))
            var left = [Float](repeating: 0, count: 1024)
            var right = [Float](repeating: 0, count: 1024)
            var interleaved = [Int16](repeating: 0, count: 2048)
            var rendered = 0
            var released = false
            sd_note_on(core.pointer, Int32(note), 0.8)
            while rendered < totalFrames {
                if rendered >= holdFrames && !released {
                    sd_note_off(core.pointer, Int32(note))
                    released = true
                }
                // Split at the exact note-off boundary, including short notes.
                let boundary = released ? totalFrames : holdFrames
                let frames = min(1024, boundary - rendered)
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        sd_render(core.pointer, l.baseAddress, r.baseAddress, Int32(frames))
                    }
                }
                for index in 0..<frames {
                    // Fade any residual delay tail to zero instead of cutting
                    // the waveform abruptly at the bounded render endpoint.
                    let remaining = totalFrames - rendered - index - 1
                    let fade = min(Float(remaining) / Float(fadeFrames), 1)
                    interleaved[index * 2] = pcm16(left[index] * fade)
                    interleaved[index * 2 + 1] = pcm16(right[index] * fade)
                }
                let data = interleaved.withUnsafeBytes { Data($0.prefix(frames * 4)) }
                try file.write(contentsOf: data)
                rendered += frames
            }
            try file.close()
            return url
        } catch {
            try? file.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private static func pcm16(_ value: Float) -> Int16 {
        guard value.isFinite else { return 0 }
        return Int16((min(max(value, -1), 1) * Float(Int16.max)).rounded()).littleEndian
    }

    private static func waveHeader(frameCount: Int, sampleRate: UInt32) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let dataBytes = UInt32(frameCount * 4)
        data.append(contentsOf: "RIFF".utf8)
        append(dataBytes + 36)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16))
        append(UInt16(1)) // PCM
        append(UInt16(2)) // stereo
        append(sampleRate)
        append(sampleRate * 4)
        append(UInt16(4)) // block alignment
        append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(dataBytes)
        return data
    }
}
