# SOUND DIHSIGN

Version 0.2 adds a personal preset pool to the native iPhone sound-design app. Import your Serum `.fxp` presets, choose donors, generate a remix, and try it on the bottom keyboard. The white interface uses native controls, illustrated parameter guides and a simple Connect sheet. A macOS companion transfers app patches and renders audio.

The iPhone uses an independent synthesis engine. Its Serum imports are **simplified previews**, and experimental `.fxp` exports have been checked as binary files but have **not been loaded or compared in Serum**. This is not a complete Serum 2 recreation; native `.SerumPreset` writing remains unavailable.

## Update and run on your phone

Use a Mac with a compatible Xcode 15 or newer and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The iPhone requires iOS 17 or newer; the companion requires macOS 14 or newer.

1. Download the `iphone-starter` branch from [GitHub](https://github.com/Breezybeats/SOUND-DIHSIGN/tree/iphone-starter) using **Code → Download ZIP**, then unzip it.
2. Close any previously opened SOUND DIHSIGN project. In Terminal:

   ```bash
   cd ~/Downloads/SOUND-DIHSIGN-iphone-starter
   # Install once if you use Homebrew and do not already have XcodeGen:
   brew install xcodegen
   xcodegen generate
   open SoundDihsign.xcodeproj
   ```

3. Click the blue project icon, select **TARGETS → SoundDihsign → Signing & Capabilities**, enable automatic signing and select your Apple development team.
4. Connect an unlocked iPhone, trust the Mac, select your phone as Xcode's destination and press **⌘R**. Enable iPhone Developer Mode if requested.

Regenerate the Xcode project after each source update so new Swift files and assets are included. Re-select the signing team if regeneration clears it. Choose **SoundDihsignCompanion** to build the Mac app instead.

The local Swift package supplies the C++ engine and links the system zlib library. This repository includes source, not a signed iPhone app or an App Store release. Apple SDK compilation, signing and on-device validation are still required.

## Make a personal sound pool

1. Put your own `.fxp` or `.sdpatch` files in the iPhone **Files** app using iCloud Drive, AirDrop or another file provider. If they are in a ZIP, extract it first; import the individual preset files from the resulting folder.
2. Tap **Import presets** under the patch name, or **Sound pool** after importing your first files.
3. Tap **Import presets** in the pool, use the Files picker's selection controls and choose multiple preset files.
4. Check the presets to use as donors. **All** selects the library; **Clear** deselects it. Choose at least two presets for new combinations; a single donor retains its stored values.
5. Tap **Generate remix**. The app returns to the instrument so you can play the bottom keyboard. Open **Sound pool** again for another combination, or use **Undo** there to restore the previous sound.
6. Use a control's lock button, or **Keep controls fixed** in the pool, to preserve settings during app-patch randomization. Long-press the oscillator octave row to lock its octave.

Imports are copied into this device's private app storage. The app supports up to 512 personal presets and does not upload them. The 299 user-supplied presets used for validation are **not bundled in the source ZIP, GitHub repository or app**. Import your own copies on the phone.

Two generation paths are available:

| Selected pool | Result |
| --- | --- |
| Only supported Serum FXPs, with no locked controls | Mix every stored normalized parameter column in the selected 260-, 273- or 299-control schemas. Export an experimental Serum FXP and an app preview. |
| Includes app patches, or has any locked controls | Mix available app controls, keeping oscillator mode/table and audio assets together. Export the resulting `.sdpatch`. |

For the Serum path, the base uses the largest selected schema and prefers presets with the most embedded oscillator banks. Each parameter column draws a value from a selected preset that contains that column. The base retains its embedded assets, all 32 raw modulation slots and effect order. Its original Serum program name remains in the exported FXP even though the phone labels the result as a remix. This mixes stored settings; it does not merge every preset's wavetable, LFO drawing or routing graph.

Some presets depend on external wavetables that are absent from the FXP. Those oscillators are muted in the phone preview instead of receiving a substitute table. Preset details report missing assets and unsupported effects or motion. Noise sample payloads can remain intact in an experimental export without being playable in the phone engine. Check the exported result in your installed Serum before relying on it.

Experimental FXP export is available immediately after generating an unlocked Serum-only remix. Editing app controls or modulation invalidates it; generate again to create another FXP. The app's edited controls and routes can always be saved in its own patch format. See [transfer details](docs/TRANSFER.md).

## Understand and connect controls

Each slider shows a small illustration and a plain explanation of its function. The drawings respond to stored control values; they are guides rather than meters of live audio or modulation.

Tap **Connect** below a control, choose **LFO 1**, **Envelope**, **Velocity** or **Macro 1**, set a signed depth and tap **Save**. A new connection takes effect after Save. Existing connection depths preview live; Cancel restores their original amounts. The sheet includes a keyboard for auditioning saved connections. **Remove this connection** disconnects the selected source. Dragging a source onto a slider remains available.

Connect **Macro 1** to several controls, then move its slider to shape them together. This groups controls under one modulation source; it does not turn an arbitrary filter or pitch knob into a modulation source.

## Sound engine and interface

The app exposes 55 parameter IDs. Its previews use only the Serum settings understood by this engine; retaining more raw settings in an FXP does not add their DSP to the phone.

- Three oscillators offer wavetable, sample, granular and basic additive spectral modes. Original built-in tables and personal audio/wavetable imports are supported.
- **Generate Wavetable** on each oscillator creates 16 original, smoothly morphing harmonic frames of 2,048 samples. It retains tuning, levels, routes and other oscillator settings.
- Independent oscillator octave buttons span **−4 to +4**, preserving semitone and fine tuning. The bottom multitouch keyboard has separate octave buttons, master level and panic.
- Eight-voice polyphony, up to four unison voices, sub/noise, pan, detune and mode-dependent warp; one amplitude ADSR, resonant low-pass filter, drive and fixed-time stereo delay.
- One sine LFO, velocity, one macro and sixteen app modulation routes. Detailed settings stay under **Advanced**.
- White panels, blue accents, key feedback and gentle transitions. A brief liquid introduction can be skipped with **Open studio**; Reduce Motion removes moving liquid and spring/scaling effects.
- The macOS companion previews `.sdpatch` files and renders stereo WAV. Transfer uses explicit Files/AirDrop import; automatic pairing and cloud synchronization are future work.

`.sdpatch` JSON stores app parameters, routes and embedded samples/tables, with a 32 MiB file limit. Update both apps when transferring new patches to an older companion; older readers reject newly introduced octave parameter IDs. Original starter patches are in [examples](examples/). The [product plan](docs/PRODUCT_PLAN.md) describes the remaining Serum-inspired features and engine limits.

The `CoverArtwork` asset slot is still empty, so the introduction uses procedural artwork. To add your original cover, save it as PNG/JPG, open `ios/Assets.xcassets` in Xcode, select **CoverArtwork**, drag the image into its **Universal** slot and rebuild. The cover has not been embedded or verified on a device.

## Portable checks

Use the existing isolated checkout; no Git worktree is needed. Audio tests require a C++17 compiler and pthread support. Preset parsing and library tests also require zlib development headers/library; the Foundation library test needs Swift 5.9 or newer.

```bash
bash scripts/check.sh
SANITIZE=1 bash scripts/check.sh
bash scripts/check_presets.sh
SANITIZE=1 bash scripts/check_presets.sh
python3 -m unittest discover -s tests -p 'test_serum_inspector.py'
bash scripts/check_library.sh
```

The preset and library scripts accept an optional directory of your private FXPs:

```bash
bash scripts/check_presets.sh /path/to/your/presets
bash scripts/check_library.sh /path/to/your/presets
```

They take positional file/directory arguments, not a manifest flag. Set `SWIFTC=/path/to/swiftc` if the Swift compiler is not on PATH. Build products go under ignored `.build/portable`; the library test uses a temporary private test directory. CMake also defines audio and preset parser test targets and requires zlib.

See [validation](docs/VALIDATION.md) for results actually obtained, fixture privacy and outstanding Apple-platform/Serum checks. The starter bundles original content; third-party preset or wavetable packs must be imported personally unless redistribution permission is available.
