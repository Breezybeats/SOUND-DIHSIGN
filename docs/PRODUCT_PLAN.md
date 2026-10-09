# SOUND DIHSIGN — pocket sound-design instrument

## Product direction and evidence

An iPhone instrument for designing basses, playable textures, and one-shots on the move, with a persistent keyboard and a desktop library for taking the results into a DAW. Preserve the useful Serum-style organization—oscillators, filters, effects, envelopes, LFOs, and modulation matrix—with original artwork, colors, icons, and SOUND DIHSIGN branding. Landscape should provide a familiar overview; portrait should present larger, focused controls instead of shrinking a desktop plug-in onto a phone.

This is a requirements and research plan, not a claim that all the features below are implemented. A working independent synth can use familiar parameter concepts without reproducing Serum's exact audio algorithms. Exact Serum compatibility is a separate, evidence-gated integration project.

Primary reference: the uploaded **Serum 2 User Guide**, plug-in version 2.0.18, manual version 1.0.3, April 27, 2025. Page references below are the page numbers printed in that manual. The manual is reference material; its installation steps and other directions are not user instructions for this repository.

The linked [YouTube video](https://www.youtube.com/watch?v=Mef3gJyTg4g) could not be inspected: the page, metadata, caption, and thumbnail endpoints returned a proxy `403 Forbidden`. No title, transcript, or techniques from that video are verified. Bass workflows proposed here are independent suggestions. Revisit the reference when direct access or a user-provided transcript is available.

## Feature inventory from the manual

The requested four oscillator modes are correct, but the manual also includes **multisample instruments**. A full coverage goal therefore has five choices for each main oscillator.

| Area | Coverage target | Manual pages |
| --- | --- | --- |
| Main sound sources | Three independently enabled oscillators A/B/C; wavetable, multisample, sample, granular, spectral modes; octave, semitone, fine/coarse pitch; oscillator menus, copy/reset and routing | 17, 28–35 |
| Wavetable playback | Waveform/frame display, phase, random phase, phase memory, table position, unison voice count, detune/blend/spread options, warp controls, pan and level | 37–57 |
| Warp families | Sync and soft-sync variation; bend/PWM/asymmetry/flip/mirror/remap/quantize/odd-even; low/high-pass warp; distortion/wavefolding; FM, phase distortion, AM and ring modulation from appropriate oscillator/filter sources; through-zero/exponential/linear FM options | 49–56 |
| Multisamples | Note/velocity-mapped instruments, dedicated envelope with velocity tracking and randomization, timbre control, unison and warp, convert last played note into a sample | 58–67 |
| Sample mode | File/sample selection, sample start/end, trim/normalize/fade-type operations, slice markers and slice handling, loop settings, loop start/end and crossfade, scan, unison, warp, pan/level, sample-to-wavetable conversion | 68–84 |
| Granular mode | Sample and loop regions, crossfade, grain window, unison, X/Y grain control, scan (including freeze/reverse), density, grain length, grain randomization, warp, pan/level, sample-to-wavetable conversion | 85–103 |
| Spectral mode | Spectrogram and time/frequency regions, loops/crossfade, unison, X/Y control, scan/time-stretch, phase locking and transient preservation, spectral cutoff, drawn spectral filter masks or wavetable masks, wet/dry mix, warp, pan/level | 104–122 |
| Sub oscillator | Sine, rounded rectangle, triangle, saw, square and pulse; octave/coarse pitch, phase, pan/level, routing | 123–127 |
| Noise oscillator | Noise/sample selection and user import, one-shot or loop, start offset, randomization, pitch/fine, pan/level | 128–132 |
| Two voice filters | Source selection and flexible routing; cutoff, resonance, drive, type-specific variable control, pan/mix/level; key tracking; frequency/phase response displays with FFT overlays | 133–143 |
| Filter families | Ladder and state-variable LP/HP/BP/peak/notch; dual and morphing filters; comb/flanger/phaser variants; EQ/ring/sample-hold/all-pass/reverb; formant/band-reject/distorted-comb/scream; newer circuit models, drawable filters and diffusor | 135–139 |
| Mixer and buses | Oscillator and filter levels/pans, sends, filter routing; MAIN, BUS 1, BUS 2 and direct output paths | 144–151 |
| FX racks | Three racks (MAIN/BUS 1/BUS 2), rack presets, reorder/copy/bypass modules, save racks, modulate effect parameters, nested splitters | 152–160 |
| Envelopes | Four envelopes, attack/hold/decay/sustain/release with editable curves, time or beat units, zoom, legato behavior; ENV 1 also controls the voice amplifier | 183–187 |
| LFOs | Ten independent LFOs; point/step/ramp drawing, enlarged editor, shape library; Normal/Path/Lorenz/Rossler/S&H types; free/retrigger/envelope, mono/poly, direction, grid, host phase, beat/Hz rate, triplet/dotted, rise/delay/smoothing/phase | 188–194 |
| Modulation gestures | Drag envelope/LFO/macro handles onto eligible controls, show destination count and depth ring; signed depth/polarity; copy wavetable shape to LFO and vice versa; modulate LFO points | 187, 194–200, 207 |
| Other modulation sources | Velocity/note, eight macros, oscillator/filter audio outputs, note-on random/alternation, voice control, pitch bend/mod wheel/pressure, expression and MPE axes | 201–211 |
| Matrix | 64 routing slots and 49 sources in the documented version; source, editable response curve with rise/fall smoothing, signed amount, polarity, destination, auxiliary source/inversion, output display, bypass/delete/reorder | 209–214 |
| Voice behavior | Mono/legato/polyphony and voice count; portamento time and curve, always/scaled options | 215–218 |
| Clips | MIDI clip banks, piano-roll note/velocity editing, grid/zoom/fold/length, clip settings/triggers, recording, MIDI output and macros | 219–243 |
| Arpeggiator | Banks and editable patterns; transpose/playback/retrigger/velocity settings, triggering and MIDI output | 244–266 |
| Performance keyboard | Visible keyboard, transpose, key/scale, swing and oscillator mapping | 25, 267–273 |
| Wavetable creation | Draw waveforms, FFT harmonic editing, frame insert/delete/copy/sort, formula parser, single/all-frame operations, morphing, import/export and save | 274–290, 304–311 |
| Audio/image import | Multi-/single-cycle audio import, advanced import settings, image-to-table, embeddable custom wavetable content | 291–303 |
| Globals | Voice variation/sequence configuration, quality/oversampling, smoothing and Serum 1 compatibility behavior; concert pitch and tuning-file/MTS-ESP settings | 312–322 |
| Library and exchange | Preset metadata/categories/tags/rating/search/preview, packs, custom asset embedding, rendered WAV of last note/chord, preset initialization/reset and resampling | 21–23, 323–339 |
| Workflow helpers | Tooltips, value entry/fine adjustment, undo/redo, output metering/volume, preset and configuration defaults | 23–27, 323–326 |

The wording “anything can modulate anything” should become **any registered, eligible numeric destination**. File pickers, enable switches, voice allocation, and structural routing changes require separate handling. Different destinations may need different update rates, smoothing, ranges, and voice scopes. Audio-rate modulation needs a dedicated audio-rate path, not a UI knob update loop. The matrix and drag gesture must edit the same underlying route records.

## Complete FX family checklist

The manual's table of contents omits Delay, but its controls are documented on pages 165–167. Include it in the inventory. This table groups essential parameter families; it does not imply a verified match to Serum DSP.

| Module | Parameter/function families to account for | Pages |
| --- | --- | --- |
| Bode frequency shifter | Mono input, shift/range/direction/width, delay and feedback, shifted-signal balance, blur, mix/level | 161 |
| Chorus | Rate/sync, two stereo delay pairs, modulation depth, feedback, LP/HP wet filter, mix/level | 162 |
| Compressor | Single or multiband upward/downward operation, threshold/ratio/attack/release/makeup, crossover/band controls, mix/level; limiter mode and its latency | 162–164 |
| Convolve | Imported/embeddable IR, size/tone/minimum-phase, pre-delay/sync, attack/decay/damping/IR gain, mix/level | 164–165 |
| Delay | Stereo/ping-pong/tap-to-delay, independent left/right times and scalar offsets, beat/ms timing and linking, feedback, wet filter, mix/level | 165–167 |
| Distortion | Type, pre/post filter and morphable filter response, cutoff/Q, drive or custom dual-waveshaper morph, mix/level | 167–168 |
| Equalizer | Two bands with type/frequency/Q/gain, output level | 169–170 |
| Filter FX | Master effect version of voice filter, type/cutoff/resonance/drive/variable control and display, mix/level | 170–172 |
| Flanger | Rate/sync, depth, feedback, stereo phase, mix/level | 172–173 |
| Hyper/Dimension | Micro-delay chorus voice count/rate/detune/retrigger/mix, dimension widening controls, level | 173–174 |
| Phaser | Rate/sync, pole count, two depth controls, frequency/feedback/stereo phase, mix/level | 174–175 |
| Reverb | Plate, Hall, Vintage, Nitrous and Basin types; type-specific size/pre-delay/decay/cuts/damping/diffusion/modulation, mix/level | 175–177 |
| Low/High splitter | Crossover and independent low/high nested FX racks, bypass, level | 177–178 |
| Low/Mid/High splitter | Two crossovers and three independent nested FX racks, bypass, level | 179–180 |
| Mid/Side splitter | Independent mid/side nested FX racks, bypass, level | 180–181 |
| Utility | L/R polarity, LP/HP filters, mono-bass crossover, width/balance, mix/level | 182 |

Repeated module instances and rack ordering should have stable IDs so their modulation assignments survive moving a module. Preserve routing trees in the patch format; a flat “effects enabled” array loses splitter/rack behavior.

## iPhone interaction design

- **Persistent audition strip:** multitouch keyboard at the bottom, octave arrows, latch/hold, pitch/mod controls and a compact output meter. Keyboard touch position can provide velocity; an optional pad grid and scale lock suit one-handed use. Provide an explicit panic/all-notes-off action.
- **Portrait:** segmented A/B/C oscillator cards with a mode menu, waveform/sample canvas, and common pitch/level controls. Show mode-specific controls beneath. Filters, FX, modulation, sequencer and library have focused views while the keyboard stays reachable.
- **Landscape:** three oscillator cards plus Sub/Noise, two filters, lower envelope/LFO panes and keyboard. Expand a graph or rack with one tap. Keep 44-point touch targets and readable value labels even when screen space is tight.
- **Knobs:** vertical drag for coarse changes, precision modifier gesture, tap value entry and double-tap reset. Show units and live modulation rings. A knob should retain its base value while modulation adds a bounded signal.
- **Modulation:** long-press and drag an LFO/envelope/macro chip; valid destinations highlight, drop opens signed depth/polarity controls. Offer “Assign modulation” from the knob menu as an accessible, non-drag alternative. Route list and rings update together; remove/bypass should be undoable.
- **Editors:** full-screen envelope/LFO/sample/spectral editors with a safe inset above the keyboard, snap controls, zoom and reversible edits. Retain pitch and audition transport while drawing.
- **Performance view:** eight named macros, X/Y pad and keyboard, with four macros prominent at a time. Use original macro names such as Motion, Growl, Air and Space rather than copying preset artwork.
- **Mobile behaviors:** offline-first projects and assets, autosave/recovery, audio-interruption and route-change handling, headphones/speaker switching, CPU/voice meter and an explicit quality setting. Touch controls and audio rendering must remain independent.

## Bass-design additions worth prioritizing

1. **Protected sub lane:** independent clean sub routing, phase reset and mono-bass crossover. Keep low-end energy predictable while mid/high layers are widened or distorted. Serum's routing and Utility module support the underlying concepts (pp. 123–127, 144–151, 182).
2. **Motion recipes:** original preset templates for wavetable-position movement plus filter motion, two-oscillator FM growls, formant sweeps, granular freezes and rhythmic spectral masks. Explain which parameters each macro changes. These are proposed workflows, not verified content from the linked video.
3. **Resample in place:** render a held note or short phrase, then send it to sampler, granular, spectral or wavetable import. Save the source patch alongside each render so sound exploration remains reversible (manual pp. 22–23, 324).
4. **A/B sound snapshots:** level-matched comparison, patch history and optional locked sub/pitch when trying bounded random variations. Randomization should honor parameter ranges and leave a recoverable snapshot.
5. **Bass analysis:** compact spectrum, note/fundamental label, peak/RMS levels, mono audition and low-band solo. A user-selectable output ceiling helps audition on headphones without sudden jumps between patches.
6. **Rhythm preview:** local tempo, syncable LFOs, a short bass phrase and one-tap note recording. Add clip/arp editing later so a designer can judge motion in context instead of repeating one static note.
7. **Import and capture:** Files picker, recording with separately requested microphone permission, trim and zero-crossing/loop-crossfade tools, plus tags such as growl, metallic, vowel, smooth, one-shot and texture.
8. **AUv3 and MIDI:** native iOS Audio Unit instrument extension, USB/Bluetooth MIDI input, expressive keyboard/MPE and host tempo support after the standalone engine is reliable.

## Wavetables and one-shots

Ship an original, documented starter bank: geometric shapes and blends, pulse-width series, additive odd/even harmonics, formant-like harmonic peaks, FM sweeps, folded shapes, metallic/inharmonic series and resampled original bass textures. These waveform families are useful for bass design; no claim is made here about measured popularity or endorsement by the video creator.

For internet banks, prefer explicit commercial redistribution licenses, CC0/public-domain content, or commissioned assets. “Free download” and “royalty-free music use” do not establish permission to bundle a sample or wavetable in an app. For every shipped asset keep a provenance manifest: creator, original URL, license text/version, attribution, redistribution rights, commercial-use rights, hash and any processing performed. Include required attribution in the app.

The [Adventure Kid waveform collection](https://www.adventurekid.se/akrt/waveforms/adventure-kid-waveforms/) is a source candidate to investigate for single-cycle material; its current terms and redistribution requirements must be checked before bundling. Paid or producer “free” bass banks can be supported through **personal user import** when the user's license permits it. No third-party bank has been downloaded or approved for redistribution by this plan.

Do not bundle Serum factory wavetables, samples, presets, impulse responses, screenshots or UI artwork without permission. The manual notes that factory oscillator content cannot be embedded through the preset embedding control (p. 22), so transfer must distinguish a factory reference from a portable custom asset.

For custom wavetable exchange, support WAV table import/export with explicit frame sizing and metadata. Serum describes 2048 samples per frame and up to 256 frames (p. 38). Validate format with actual Serum imports; a WAV file containing arbitrary audio is not automatically a correctly framed wavetable. One-shot files need original sample rate, channel count, root note, loop/slice markers and asset hash in the app project.

## Preset compatibility and desktop companion

The manual explicitly names `Serum 2 Presets/Presets/User/default.SerumPreset` and `defaultFX.SerumPreset` (p. 324). Use **`.SerumPreset`** when discussing the documented Serum 2 native preset format. Do not label app JSON as `.fxp` or `.SerumPreset`: renaming a file does not make it a Serum preset. The manual describes load/save/embedding behavior, not a public binary/serialization specification or a third-party preset-writing API.

The documented default content roots are `/Library/Audio/Presets/Xfer Records/` on macOS and `/Documents/Xfer/` on Windows (p. 344); Windows OneDrive can change the documents location (p. 15). A desktop companion must let the user select their actual Serum 2 preset folder, rather than assuming a universal absolute path.

| Export/transfer | What it preserves | Honest status and limitation |
| --- | --- | --- |
| App patch/project | All app parameter values, mode settings, modulation graph, FX topology and asset references | Use a versioned app-specific format; readable by SOUND DIHSIGN, not by Serum |
| WAV render | Audible result for chosen notes/phrase, duration and quality | Works as audio exchange; does not preserve editable oscillator/FX/modulation state |
| Custom wavetable WAV or sample WAV | Table/sample content | Asset import into Serum can work after format validation; does not transfer the entire patch |
| MIDI phrase/parameter recipe | Notes and a human-readable parameter mapping | Useful for recreation; MIDI alone is not complete preset serialization |
| Genuine native Serum 2 preset | Serum's editable state, routing, modulation and referenced/embedded content | Integration research required; no verified writer, SDK or complete mapping currently established |

Recommended first companion: a **macOS** patch inbox (the user's selected first platform) that receives app projects and WAV assets, previews them, organizes/tag-searches them, shows transfer progress and opens the destination folder. Windows can follow. A production desktop application should provide native file access and reliable drag-out. Initial exchange can use Files/AirDrop or an explicit import. Local-network pairing or cloud sync can follow, with conflict handling and no silent overwriting of patches.

For genuine Serum export, pursue Xfer documentation/cooperation or another demonstrably authorized integration route. A desktop host running the user's licensed Serum 2 might load supported assets and apply exposed parameters, with Serum saving its own native preset, but this remains a feasibility proposal: host automation may not expose wavetable editing, nested racks, modulation structures or every mode parameter. Do not promise that this route works until tested. Do not bundle Serum itself or claim that desktop Serum runs on iOS.

Compatibility acceptance must include a parameter-by-parameter map, enum/range/scaling verification, effect order/bus/splitter topology, envelopes/LFO shapes and modes, mod depths/polarity/auxiliary sources, asset portability and actual preset-load tests in a specified Serum 2 version. Compare rendered audio with phase and randomization fixed, then evaluate aliasing, FM, granular/spectral transients and effect tails. Identical knob labels and numbers alone do not guarantee identical sound. If exact sound is the requirement, a licensed matching engine or proven round-trip implementation is a release gate.

## Architecture and phased delivery

Use a stable, versioned patch model from the first build: parameter registry with IDs, units/ranges/scopes; A/B/C oscillator modes; Sub/Noise; filter and mixer routing; ordered/nested effects; modulator settings; modulation route records; sequencer; asset manifest and schema migration. Keep the synthesizer engine separate from UI, transfer and any Serum-specific adapter.

A production iPhone app should use a native low-latency audio path (AVAudioEngine/custom Audio Unit), a real-time-safe DSP core and SwiftUI/UIKit touch controls. A portable C++ DSP core can also power AUv3 and a future desktop instrument. The audio callback must avoid allocation, file/network I/O and blocking locks; smooth control changes and precompute/load assets off the audio thread. A Web Audio prototype is useful for interaction review, but it does not establish native iPhone latency, thermal behavior, AUv3 support or full DSP equivalence.

| Phase | Deliverable | Completion evidence |
| --- | --- | --- |
| 1 — Playable design prototype | Original phone UI, A/B/C selection, basic wavetable engine, Sub/Noise, keyboard, envelope, LFO-to-knob route, essential effects, project save/load and WAV render | Audio actually responds to controls; drag/tap assignment edits a real route; exported project round-trips; mobile layout works; clearly list approximations/missing features |
| 2 — Native iPhone foundation | Xcode iOS project, real-time audio engine, multitouch/MIDI, autosave, Files/share import/export, interruptions and route handling | Build/sign/test on a Mac with Xcode and on a physical iPhone; measure glitches, latency, CPU and thermal behavior at the stated voice/quality settings |
| 3 — Sound-design depth | Real sampler, granular and spectral engines; dual filters, unison/warp/FM; all envelope/LFO/macro controls; matrix, full effect families and asset tooling | DSP tests per mode and route, aliasing/phase/smoothing checks, deterministic export tests, measured performance budget and truthful supported-feature matrix |
| 4 — Companion and performance | Desktop inbox/library, paired transfers, native drag-out, AUv3, clip/arp tools and expressive MIDI | Transfer and recovery tests on Mac/Windows; AUv3 host tests; actual asset import into Serum; failure/conflict feedback |
| 5 — Verified Serum exchange | Native preset interoperability for a precisely stated version/feature subset, expanded only as mappings are proven | Load exported presets in licensed Serum 2; verify routing/assets/modulation/FX and render comparison; unsupported items explicitly reported |

No App Store publication, signed native build, purchased asset bundle or licensed Serum interoperability is implied by a prototype. Record the actual implemented subset and validation results separately from this feature target. The uploaded manual supplies behavior descriptions; it does not supply source code for a full DSP recreation.
