# Validation and implementation limits

Validation date: October 9, 2026. Current machine: Linux x86_64, GCC C++17. The repository started empty. Application sources, example app patches and configuration were added; no Serum content or binary was imported.

## Executed and passed

`bash scripts/check.sh --demo /workspace/scratch/soundcore-demo.wav` compiled the portable C++ engine with warnings enabled and completed **16 scenarios / 120 assertions / 0 failures**:

1. Silence and invalid API inputs.
2. A4 pitch and semitone transposition.
3. ADSR release reaching silence.
4. Four oscillator modes producing different audio.
5. Pan, level, velocity and master controls affecting audio.
6. Wavetable position and table selection affecting audio.
7. All three oscillators, unison, fine tuning and warp.
8. Granular size, density and scan affecting playback.
9. Sample import copying source data and one-shot playback ending.
10. Wavetable import, frame interpolation and input validation.
11. Macro, envelope and bipolar LFO modulation, including a route through a macro.
12. Filter, drive, delay, sub and noise affecting output.
13. Imported wavetables suppressing out-of-band harmonics.
14. Polyphony overload and extreme controls remaining finite and bounded.
15. Note-command queue overflow avoiding stuck notes.
16. Concurrent control writes and rendering.

`SANITIZE=1 bash scripts/check.sh` repeated the suite with AddressSanitizer and UndefinedBehaviorSanitizer: **16 scenarios / 120 assertions / 0 failures**, with no sanitizer report. This does not substitute for a dedicated race detector or Apple-device testing.

The demo WAV was opened and inspected with Python's WAV reader: two channels, 48,000 Hz, 16-bit PCM, five seconds, nonzero audio. Peak amplitude was approximately 0.302 and RMS approximately 0.103. This verifies portable rendering/file output, not playback through an iPhone or the Mac companion's Swift WAV writer.

`project.yml` parses as YAML, both target source directories exist, and the local SoundCore product references are present. The macOS entitlements parse as a plist. Both example `.sdpatch` files parse as JSON. These structural checks do **not** validate Xcode generation, Swift compilation, Swift Codable round trips or App Store signing.

## Not executed in this environment

- XcodeGen generation, Swift Package build, iOS/macOS compilation, signing and installation. Swift/Xcode/Apple SDKs are absent on this Linux machine.
- iPhone touch interaction, VoiceOver, audio routing/interruption/recovery and device-specific latency/thermal/CPU behavior.
- Mac library persistence, sandbox file grants, AirDrop/Files exchange, native audio preview, Swift WAV rendering and drag into Serum.
- Native Serum preset load/save or audio equivalence. No native exporter exists.
- The linked video: watch, metadata/caption and related retrieval attempts returned proxy `403`. No video techniques were verified.
- CMake build, since CMake is absent. The equivalent direct compiler test script ran successfully.

## Important DSP boundaries

- Three original table families, four frames per family, limited harmonic content and precomputed harmonic mip levels. Imported tables support up to 256 complete frames; the phone importer currently requires 2,048 samples per frame.
- Eight voices, up to four unison voices, a generated starter one-shot and imported mono audio. Sample pitch assumes a C4 root; root-note editing, looping, slices and multisample mapping are future work. The iPhone imports audio up to ten seconds and converts it to mono 48 kHz; imported assets in a patch are limited to 480,000 sample frames per oscillator.
- Granular mode uses a bounded sixteen-grain pool per oscillator/voice. It is a basic independent implementation with different density, scan and window behavior from Serum.
- Spectral mode uses up to 24 analyzed harmonic magnitudes with additive resynthesis. It is not Serum's time-varying FFT engine and has no spectrogram, transient preservation or drawn spectral mask. Imported tables can supply harmonic shapes; arbitrary samples are analyzed relative to the starter C4 assumption.
- The filter is one stereo resonant low-pass after each voice's oscillator mix. There is no dual-filter topology, type library or flexible bus routing.
- Drive is a basic saturation stage and delay has a fixed time/feedback topology. There is no compressor, reverb, chorus, convolution or complete Serum FX rack. Warping and saturation do not implement Serum's quality/oversampling behavior and can introduce aliasing.
- One ADSR, one sine LFO, one macro and velocity feed sixteen modulation slots. Eligible continuous parameters have stable IDs; mode, table and unison selections are excluded. Macro destinations resolve once before macro sources; recursive/algebraic feedback is not supported. Granular density is logarithmic in the engine; depth values are normalized range offsets, not a verified Serum scaling map.
- Assets are immutable during rendering; imports build a new stopped engine. The render path uses no file/network I/O or explicit allocation/locks. Concurrent writes use atomics and note events have a single-producer/single-consumer queue. Do not destroy an engine or load assets while it is rendering.
- JSON app patches have a shared 32 MiB import/export limit. Large combined embedded assets can exceed that limit and export will report an error; a binary asset container is future work. The first version does not autosave an unsaved iPhone session.

## Apple-platform acceptance checklist

1. Generate `SoundDihsign.xcodeproj` with XcodeGen, build both schemes, and resolve any compiler/API issues before describing the apps as runnable.
2. Run on a physical iPhone: enable audio, play/release chords and glissandi, change octave, check panic and VoiceOver, and verify that each exposed knob affects its intended control.
3. Test all four modes, a ten-second multichannel sample import, a framed wavetable import, switching back to a built-in table, and invalid-file feedback.
4. Assign modulation by drag and by tap; edit signed depths, remove routes, and export/reimport the patch. Compare imported asset lengths, values and routing.
5. Test calls, headphone disconnection, backgrounding and media-service resets. Measure CPU, glitches, latency and heat with the maximum voice/unison/grain settings.
6. Transfer a patch containing both sample and wavetable assets to the Mac. Confirm preview/render use those assets, stop sustained notes, save/reimport and relaunch the library.
7. Render/open the Mac WAV, check base note and tail, and perform an actual sample import in licensed Serum 2. Test dragging and explicit Save WAV separately.
8. Keep native `.SerumPreset` export gated until a verified writer/integration and complete supported-feature round trip exists.
