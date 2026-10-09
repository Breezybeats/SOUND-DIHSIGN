# Validation and implementation limits

Validation date: October 9, 2026. Current machine: Linux x86_64, GCC C++17 and an official Swift 6.2 Linux toolchain. Version 0.2 adds a bounded Serum FXP parser, experimental writer and personal preset library. User-supplied presets were tested privately outside the repository; the source and app contain no supplied commercial preset files.


## Version 0.2 preset and library results

Version 0.2.2 fixes a Swift Package integration defect reproduced from the user's Xcode screenshot. SwiftPM generated an umbrella module containing only `SoundCore.h`, which did not include `SerumPreset.h`. Type-checking `Shared/PresetLibrary.swift` against that actual module reproduced the missing `sd_preset_*` declarations and the secondary expression type-checking timeout. Including `SerumPreset.h` from the umbrella header resolved that exact type-check failure. The previous Foundation harness listed both headers in a separate test module, masking this integration error even though the library's functional tests passed. The harness now uses SwiftPM's actual generated module and compiled C++ objects so a missing public interface fails the check. Apple SDK app builds remain a separate, unexecuted check.

Version 0.2.1 addresses the report that **Import patch** did not open Files. The studio now has one root `fileImporter` with a separate, persistent import kind instead of three stacked importer modifiers. That kind remains available after SwiftUI clears the presentation binding, so completion can still dispatch a patch, audio sample or wavetable correctly. The menu accepts FXPs as well as app patches; FXPs add to the personal pool, and the studio stays visible while the root picker dismisses to avoid immediately presenting a competing library sheet. Swift 5 syntax parsing and review passed for the updated iOS sources. The actual picker presentation, cancel/reopen behavior and Apple SDK compilation still require device/Xcode validation.

The private validation collection contains **299 Serum FXP files, approximately 236 MiB**. Originals remain outside the checkout under the cloud attachment directory. None is bundled, published or added as a test fixture. Public tests construct synthetic data; the real collection is an optional local test input.

The Python inspector's **11 synthetic tests passed**, and inspection of all 299 real files verified all five observed state layouts:

| Decoded state bytes | Stored normalized parameters |
| --- | --- |
| 21,524 | 260 |
| 21,804 | 260 |
| 21,808 | 260 |
| 28,232 | 273 |
| 172,736 | 299 |

The native C++ parser/writer suite completed **15 scenarios / 86,485 assertions / 299 private fixtures / 0 failures**, both normally and with AddressSanitizer/UndefinedBehaviorSanitizer:

```bash
bash scripts/check_presets.sh /workspace/attachments
SANITIZE=1 bash scripts/check_presets.sh /workspace/attachments
```

The script accepts positional file or directory paths and searches a directory recursively for `.fxp`; it does not accept `--manifest`. `/workspace/scratch/preset-library` holds inventory reports rather than the original preset files. Public users can run the synthetic suite without an argument, or provide their own preset directory.

Checks cover verified schemas, header/plugin identity, stream and size limits, finite normalized values, mapped control curves, table bounds, route polarity, supported LFO tempo subdivisions, malformed inputs, and safe C API failures. Writer tests change all raw controls while retaining non-control state bytes. Unchanged rewrites of every real fixture preserve the decoded state and asset/noise sections byte-for-byte and reparse successfully. These are structural format tests; no Serum plugin was invoked.

The actual shared Swift Foundation code and C bridge compiled with the official Linux **Swift 6.2 toolchain in Swift 5 language mode**. After the version 0.2.2 header correction, the revised harness built both C++ sources through SwiftPM, imported its generated umbrella module and linked its actual native objects. The library suite passed **7 scenarios / 3,641 assertions / all 299 private fixtures / 0 failures** through that real package interface:

```bash
SWIFTC=/tmp/sound-dihsign-swift/usr/bin/swiftc bash scripts/check_library.sh /workspace/attachments
```

The compiler path above describes this validation machine; on another machine use `bash scripts/check_library.sh` with Swift on PATH, or supply its local `SWIFTC` path. The script uses the sibling Swift package driver, with an optional `SWIFT` override, and redirects SwiftPM and compiler caches into ignored `.build/portable` directories. Tests cover private persistence, byte-identical original copies, duplicate import detection, bounded metadata without embedded asset arrays, selected donors, parameter locks, mode/table asset coupling, maximum-schema raw mixing, export/preview agreement, missing-table muting, library limits and deletion that leaves user source files intact. The test script uses an isolated temporary library and removes it afterward.

An unlocked FXP-only pool draws each raw normalized parameter column from selected donors that contain that column. It uses the largest selected parameter schema, preferring the most embedded oscillator banks among those candidates. The template's assets, all 32 raw modulation slots, effect order and original Serum program name are retained. An app-patch pool or any locked controls instead uses available app controls and coupled mode/table assets, with `.sdpatch` output. Foundation tests exercise these distinct paths; they do not validate Serum's DSP or audio.

Across the real collection, **210 oscillator wavetable banks were not embedded**. Missing external banks are reported and their oscillators are muted in app previews. **32 FXPs contain opaque Noise-bank payloads** that are retained by the FXP writer but are not rendered by SoundCore. **Three embedded banks require sample clamping for the app preview**; their original bytes remain unchanged in the experimental FXP. Even presets with complete tables may sound different because the phone does not implement all Serum oscillators, effects, LFOs or routes.

The new illustrated controls, Connect sheet, in-sheet keyboard, locks, pool selection, file picker/exporter and Undo received static review and Swift syntax parsing. Illustrations show stored parameter values, not measured audio or live modulation. Existing route depths can preview while a sheet is open; Cancel restores their amounts, while new connections wait for Save. These iPhone interactions have not been executed in this Linux environment. Editing app controls/routes invalidates the generated FXP; regenerating produces another exportable raw remix.

`Package.swift` links system zlib. The actual SoundCore Swift Package build compiled both C++ source files successfully on Linux. SwiftPM cache, configuration, security and compiler module-cache directories were redirected into the ignored `.build/swift-check` directory because this environment's home directory is read-only. CMake now requires zlib and includes both audio and preset parser test targets. The Foundation test script requires Swift 5.9+, a C++17 compiler and zlib development headers/library. Neither these portable results nor Swift syntax parsing establish that an Apple SDK build succeeds.

## Original audio core and earlier interface results

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

The original demo WAV was opened and inspected with Python's WAV reader: two channels, 48,000 Hz, 16-bit PCM, five seconds, nonzero audio. Peak amplitude was approximately 0.302 and RMS approximately 0.103. These baseline measurements verify portable rendering/file output, not playback through an iPhone or the Mac companion's Swift WAV writer.

After adding oscillator octaves and original wavetable generation, both the optimized portable suite and the AddressSanitizer/UndefinedBehaviorSanitizer suite passed **21 scenarios / 205 assertions / 0 failures**, with no sanitizer report. The five additional scenarios cover:

1. Independent octave changes on all three oscillators, preserving semitone/fine tuning, rounding octave inputs and excluding octave from modulation destinations.
2. Seed repeatability and variation, finite normalized samples, non-silent frames, near-zero DC and frame morphing.
3. Minimum/maximum generation dimensions, zero-seed behavior, invalid input rejection and unchanged output on failure.
4. Harmonic phase coherence, a retained bass fundamental and frequency limits below the wavetable frame's Nyquist frequency.
5. Generated banks loading into oscillators A/B/C and position controls changing the rendered sound.

The phone generates 16 frames of 2,048 samples off the main thread and embeds them in the patch. Static review checked retention of other oscillator settings, modulation and held-note velocities, plus stale-result cancellation. These Swift behaviors have not been executed on an Apple platform.

`project.yml` parses as YAML, both target source directories exist, and the local SoundCore product references are present. The macOS entitlements parse as a plist. Both example `.sdpatch` files parse as JSON. These structural checks do **not** validate Xcode generation, Swift compilation, Swift Codable round trips or App Store signing.

For the interface update, tree-sitter-swift parsed all 12 Swift files under `ios`, `Shared` and `macos` with **0 error or missing nodes**. All three asset catalog `Contents.json` files parse as JSON, and project YAML/source-path checks passed. The iOS project's explicit `AppIcon` setting matches `AppIcon.appiconset`; its referenced original PNG was decoded and verified as 1,024 × 1,024 RGB, without transparency. The iOS project requests light appearance for the system launch screen as well. These checks do **not** execute Apple's asset compiler. The Swift parser checks syntax only; it does **not** perform native type checking, resolve Apple SDK APIs or compile the apps.

## Not executed in this environment

- XcodeGen generation, Apple Swift Package build, iOS/macOS compilation, signing and installation. Xcode and Apple SDKs are absent on this Linux machine. The shared Foundation library has compiled here, but SwiftUI/UIKit/AVFoundation app targets and their updated interface remain uncompiled.
- iPhone touch interaction, VoiceOver, audio routing/interruption/recovery and device-specific latency/thermal/CPU behavior.
- Mac library persistence, sandbox file grants, AirDrop/Files exchange, native audio preview, Swift WAV rendering and drag into Serum.
- Loading the experimental FXP output in licensed Serum, re-saving it there or comparing its audio. The writer has structural tests but no Serum host validation. Native Serum 2 `.SerumPreset` export remains unavailable.
- The linked video: watch, metadata/caption and related retrieval attempts returned proxy `403`. No video techniques were verified.
- CMake configuration/build of the new parser target. Equivalent direct compiler scripts ran successfully; CMake target wiring was inspected.

## Important DSP boundaries

- Three original table families, four frames per family, limited harmonic content and precomputed harmonic mip levels. Imported tables support up to 256 complete frames; the phone importer currently requires 2,048 samples per frame. The random generator creates original additive bass/formant banks with fixed harmonic phases, smooth frame morphing and a shared peak normalization; the phone requests 16 frames of 2,048 samples. It does not generate samples or duplicate Serum tables.
- Oscillator octave is a discrete −4…+4 control, separate from semitone and fine tuning. Missing octave IDs in older patches default to zero. New patches retain schema version 1 but contain new parameter IDs; previously installed readers need updating, including the Mac companion.
- Eight voices, up to four unison voices, a generated starter one-shot and imported mono audio. Sample pitch assumes a C4 root; root-note editing, looping, slices and multisample mapping are future work. The iPhone imports audio up to ten seconds and converts it to mono 48 kHz; imported assets in a patch are limited to 480,000 sample frames per oscillator.
- Granular mode uses a bounded sixteen-grain pool per oscillator/voice. It is a basic independent implementation with different density, scan and window behavior from Serum.
- Spectral mode uses up to 24 analyzed harmonic magnitudes with additive resynthesis. It is not Serum's time-varying FFT engine and has no spectrogram, transient preservation or drawn spectral mask. Imported tables can supply harmonic shapes; arbitrary samples are analyzed relative to the starter C4 assumption.
- The filter is one stereo resonant low-pass after each voice's oscillator mix. There is no dual-filter topology, type library or flexible bus routing.
- Drive is a basic saturation stage and delay has a fixed time/feedback topology. There is no compressor, reverb, chorus, convolution or complete Serum FX rack. Warping and saturation do not implement Serum's quality/oversampling behavior and can introduce aliasing.
- One ADSR, one sine LFO, one macro and velocity feed sixteen modulation slots. Eligible continuous parameters have stable IDs; mode, table, unison and octave selections are excluded. Macro destinations resolve once before macro sources; recursive/algebraic feedback is not supported. Granular density is logarithmic in the engine; depth values are normalized range offsets, not a verified Serum scaling map.
- Assets are immutable during rendering; imports build a new stopped engine. The render path uses no file/network I/O or explicit allocation/locks. Concurrent writes use atomics and note events have a single-producer/single-consumer queue. Do not destroy an engine or load assets while it is rendering.
- JSON app patches have a shared 32 MiB import/export limit. Large combined embedded assets can exceed that limit and export will report an error; a binary asset container is future work. The first version does not autosave an unsaved iPhone session.
- The liquid introduction is an in-app screen, since the iOS system launch screen cannot animate. It auto-dismisses, offers Open studio to skip and uses a static liquid composition with Reduce Motion. The supplied cover's original bytes were unavailable; the empty CoverArtwork asset currently falls back to procedural pink/lavender artwork. Follow the README's Mac asset steps to add the original photo and rebuild.

## Apple-platform acceptance checklist

1. Regenerate `SoundDihsign.xcodeproj` with XcodeGen, including existing user projects, so the new Swift file and asset catalog are included. Reselect the signing team if needed, build both schemes, and resolve compiler/API issues before describing the updated apps as runnable. In version 0.2.1, verify **Import patch or presets** opens Files, loads a single app patch, and adds multiple FXPs to Sound pool. Cancel and reopen each import kind, alternate patch/audio/wavetable imports, and verify the correct filters and original oscillator target.
2. Run on a physical iPhone: enable audio, play/release chords and glissandi, change keyboard octave, check panic and VoiceOver, and verify that exposed sliders and Advanced settings affect their intended controls.
3. Generate a wavetable in each of A/B/C, including while holding notes at different velocities. Verify a fresh table, working position morphing and unchanged other-oscillator settings, semitone/fine tuning, levels, routes and held-note velocities. Reset/import a patch or change mode/table during generation; confirm a stale result cannot overwrite the new choice.
4. Test oscillator octave −4/+4 bounds, disabled limit buttons, changes by exactly one octave and independence from other oscillators, semitone/fine tuning and keyboard octave.
5. Test all four modes, a ten-second multichannel sample import, a framed wavetable import, switching back to a built-in table, and invalid-file feedback.
6. Tap Connect, choose each source, adjust signed depth and Save; audition with the sheet keyboard. Verify that new routes wait for Save, existing depth previews restore on Cancel/swipe dismissal, and Remove affects the selected connection. Connect Macro 1 to multiple controls and check grouped movement. Also test drag assignment and inspect the value-driven illustrations. Export/reimport `.sdpatch` and compare parameters, samples, tables, octaves and routes; old patches missing octave IDs must load at octave zero.
7. Test liquid introduction auto-dismissal and Open studio, portrait/landscape layout, Reduce Motion and VoiceOver. Add the supplied photo to CoverArtwork, rebuild and check its display; also verify the empty-asset fallback.
8. Test calls, headphone disconnection, backgrounding and media-service resets. Measure CPU, glitches, latency and heat with the maximum voice/unison/grain settings, including generated banks.
9. Transfer a patch containing sample and generated/imported wavetable assets to the updated Mac companion. Confirm preview/render use those assets and octave settings, stop sustained notes, save/reimport and relaunch the library.
10. Render/open the Mac WAV, check base note and tail, and perform an actual sample import in licensed Serum 2. Test dragging and explicit Save WAV separately.
11. Import multiple personal FXPs through Files, close/relaunch the app and verify persistence, duplicate handling, search, selection, removal, missing-asset warnings and preview muting. The source ZIP must not contain the validation presets. Extract archives before importing individual files.
12. Generate from two or more selected FXPs with no locks; inspect the experimental export in licensed Serum, including template assets, names, routes and effects. Compare iPhone preview limits explicitly. Repeat with mixed `.sdpatch` donors and locks, check asset retention and Undo, and confirm that these results offer app-patch export rather than FXP.
13. Edit a generated sound's app controls/routes and verify that FXP export disappears until regeneration. Confirm that opening/canceling an unchanged Connect sheet does not invalidate it, while actual preview edits can invalidate it even if their depths are restored.
14. Keep native `.SerumPreset` export gated until a verified writer/integration and complete supported-feature round trip exists. Structural FXP validity does not establish that Serum loads the file or reproduces the phone's sound.
