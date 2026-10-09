# SOUND DIHSIGN

A native iPhone sound-design starter with a macOS transfer companion. The white, minimal interface uses native sliders and segmented controls, with detailed settings tucked into Advanced. The portable audio engine is independent of Serum.

This is a first implementation, **not a complete Serum 2 recreation**. The uploaded guide informs the [full product plan](docs/PRODUCT_PLAN.md), including the missing modes, effects, editors and performance features. Exact Serum DSP and native `.SerumPreset` export are not implemented or verified.

## Current implementation

- Three main oscillators; original wavetable families; sample playback, granular playback and basic additive spectral resynthesis. These algorithms do not reproduce Serum's engines.
- Each oscillator has a **Generate Wavetable** button that creates an original random harmonic bank: 16 smoothly morphing frames of 2,048 samples. Generation runs off the main thread, selects wavetable mode and embeds the result in the app patch while retaining tuning, levels and modulation.
- Eight-voice polyphony, up to four unison voices, sub/noise, pitch, level, pan, detune and a basic phase-warp control.
- Independent oscillator octave buttons span **−4 to +4 octaves**, without overwriting semitone or fine tuning. The keyboard has its own separate octave controls.
- One amplitude ADSR, resonant low-pass filter, drive, fixed-time delay, one LFO, velocity and one macro, with 16 modulation routes.
- Native iPhone multitouch keyboard with slides, octave controls and panic; touch controls; drag or tap modulation assignment; sample and framed-wavetable import; app-patch save/load.
- White panels, blue accents, animated key feedback and gentle transitions. A brief pink/lavender liquid introduction offers **Open studio** to skip; Reduce Motion disables liquid movement, scaling and spring transitions.
- macOS app-patch library, preview, parameter recipe and stereo WAV rendering. Transfer uses Files/AirDrop followed by explicit import; automatic pairing and cloud synchronization are future work.
- Versioned `.sdpatch` JSON stores app parameters, modulation and embedded imported or generated assets. Two original starter examples live in [examples](examples/). Older patches load with an oscillator octave of zero when that parameter is missing. Update both apps before transferring new patches to a previously installed companion; older readers reject the new octave parameter IDs.

Controls affect the custom engine's parameters. They are not a verified parameter map to Serum. Spectral mode is harmonic analysis/resynthesis, not a time-varying FFT spectral editor. Detailed engine constraints are recorded with the validation results.

## Open on a Mac

Required: Xcode 15 or newer, macOS 14 or newer, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). For an iPhone use iOS 17 or newer.

```sh
cd /path/to/SOUND-DIHSIGN
# If XcodeGen is absent and you use Homebrew:
brew install xcodegen
xcodegen generate
open SoundDihsign.xcodeproj
```

Choose **SoundDihsign** to run the phone app, or **SoundDihsignCompanion** for the Mac app. Select your development team under Signing & Capabilities before installing on a physical iPhone. The local Swift package supplies the shared C++ engine; it has no third-party package dependencies. `project.yml` generates the two targets and their patch document declarations.

**After updating an existing checkout, run `xcodegen generate` again** to include the new launch view and asset catalog. Close the project first, regenerate it, and reopen `SoundDihsign.xcodeproj`; select your signing team again if regeneration clears it.

The supplied cover is visible in chat, but its original image file was unavailable to embed. The `CoverArtwork` asset slot is empty, so the introduction currently shows its procedural liquid artwork. To use your cover on the Mac:

1. Save the original cover as a PNG or JPG.
2. Regenerate the project as above, then open `ios/Assets.xcassets` in Xcode and select **CoverArtwork**.
3. Drag the saved image into its **Universal** image slot.
4. Build and run again on your iPhone.

The Linux cloud environment cannot build or sign iOS/macOS applications. The updated Swift interface, animations and project configuration still require an Xcode build and on-device audio/touch validation; this repository does not include a signed app or an App Store release.

## Check the audio core in the cloud

Use the existing isolated checkout; no Git worktree is needed.

```sh
cd /workspace/SOUND-DIHSIGN
bash scripts/check.sh
# Optional memory/undefined-behavior validation:
SANITIZE=1 bash scripts/check.sh
# Optional original audio demonstration:
bash scripts/check.sh --demo /workspace/scratch/soundcore-demo.wav
```

A C++17 compiler and pthread support are required. The script preserves failure exit codes and writes build products under ignored `.build/portable`. CMake configuration is also supplied for machines with CMake installed. See [validation](docs/VALIDATION.md) for the checks actually run and the remaining Apple-platform checks.

## Getting sounds to Serum

Export an app patch to Files on the iPhone, send it to the Mac with AirDrop, and import it into the companion. The companion uses the same custom engine to preview it and render WAV audio. Import that WAV into a Serum sample oscillator to use the recorded sound; it does not preserve an editable oscillator, modulation or effect chain.

Serum 2's native format is `.SerumPreset`. The guide does not specify a third-party writer. A genuine exporter needs a verified format/integration, complete parameter mapping and tests loading the result in licensed Serum 2. App JSON is never renamed to pretend it is a Serum preset. See [transfer details](docs/TRANSFER.md).

The starter ships original generated audio content. Third-party internet wavetable packs need pack-specific redistribution permission before bundling; personal imports are available. Serum factory content is not bundled.
