# iPhone → macOS → Serum

Version 0.2 offers three different outputs. The iPhone and Mac companion use SoundCore, an independent engine with a limited set of Serum-inspired controls.

| Output | Preserves | Current destination |
| --- | --- | --- |
| `.sdpatch` | Editable app controls, understood routes and embedded samples/tables | SOUND DIHSIGN on iPhone or its Mac companion |
| Experimental `.fxp` | A generated Serum raw-parameter remix with its base preset's remaining state/assets | Transfer to Mac and test in licensed Serum; loading is unverified |
| Rendered WAV | The app engine's recorded sound, including its effects | Import audio into a Serum sample oscillator |

Native Serum 2 `.SerumPreset` writing remains unavailable. Renaming an app patch or audio file does not convert it into a Serum preset.

## Bring your preset pool onto the iPhone

1. Put your personal `.fxp` or `.sdpatch` files in Files using iCloud Drive, AirDrop or another file provider. Extract any ZIP first; the app imports individual preset files, not archives or folders.
2. Open **Sound pool → Import presets**, select multiple files and confirm the import.
3. Choose donors with their checkmarks; **All** selects the library and **Clear** deselects it. Choose at least two for new combinations.
4. Tap **Generate remix** to return to the instrument, then play the bottom keyboard. Open **Sound pool** again to use **Undo** or generate another combination.

The phone makes private copies of imported originals and stores a small local index. The library persists between launches and holds up to 512 entries. Imported source files remain unchanged. The supplied validation collection is not included in the project or app; import your own copies on the phone.

Preset details identify the controls and assets available to the phone. Serum FXP previews translate a subset of the stored settings: oscillator algorithms, effects, LFO shapes and some routes can differ or be unavailable. Missing external oscillator tables are muted rather than replaced. Opaque Noise samples are preserved for experimental export but are not rendered by SoundCore.

## Export an experimental Serum FXP

This path requires an **unlocked pool containing only supported Serum FXPs**. Generate a remix, then use **Sound pool → Export experimental FXP**, or the patch menu's **Export Serum FXP (experimental)** action when available.

1. Save the generated `.fxp` in Files.
2. Send it to the Mac using AirDrop or move it through your file service.
3. Use your installed Serum's preset-opening/import workflow to test that file. This is a preset file, so it belongs in the preset workflow rather than a sample oscillator.
4. Check the loaded settings, assets, effects, motion and sound before using the result in a project. Native loading and audio comparison have not been performed during cloud validation.

Every normalized parameter column in the largest selected 260-, 273- or 299-control schema can draw from a selected donor that contains that column. Among that schema's candidates, the generator prefers the most embedded oscillator banks. Its base retains the remaining state, embedded assets, all 32 raw modulation slots and effect order. Its original Serum program name is preserved inside the FXP; the phone's displayed remix name and saved filename do not replace that internal program name.

The result combines raw settings while keeping a single base's assets and routing structure. It does not combine all selected wavetables, custom LFO drawings or routing graphs. Required external assets can still be missing on the destination Mac. Export preserves unsupported raw state but does not make that state playable in the phone preview.

The binary writer has passed structural parsing and round-trip tests, including all 299 privately supplied files. **This does not establish that Serum loads its output or that the phone preview matches it.** It is not a Serum 2 `.SerumPreset` exporter.

Editing an app control or route invalidates the generated FXP, because those edits are not translated back into raw Serum state. Generate again for another experimental FXP, or export the edited sound as `.sdpatch`. A connection-depth preview is an edit even if Cancel later restores the depth. Opening and canceling a sheet without changing controls does not require invalidating an export.

Any parameter locks or mixed `.sdpatch`/FXP selection use the app-patch generation path instead. Available app control values are chosen from donors, oscillator mode/table and assets stay coupled, and locked controls remain fixed. Those results export as `.sdpatch` and can be rendered to WAV; an FXP export is not offered.

## Transfer an editable SOUND DIHSIGN patch

1. Export a `.sdpatch` from the iPhone patch menu using **Export patch**.
2. Save it in Files and send it to the Mac with AirDrop, a file service or a cable.
3. In **SOUND DIHSIGN Companion**, click **Import patch**, or drop the local file on its window. Select the imported patch.
4. Choose a note and click **Play preview**. **Stop / Panic** or **⌘.** stops all notes. The preview holds the note until stopped; a one-shot can end sooner.

The companion stores a validated copy under its Application Support library. In a sandboxed build that is inside its application container, under `Library/Application Support/SOUND-DIHSIGN/Library`. Removing an entry removes only the companion's copy. Embedded samples/tables, app controls, oscillator octaves and understood routes travel in `.sdpatch`, with a shared 32 MiB import/export limit.

The companion currently receives app patches, not the phone's experimental FXP exports. Send FXPs directly to the Mac for the Serum preset workflow. Update both app builds before exchanging patches with new octave parameter IDs; an older companion can reject those IDs.

There is no automatic pairing, server, shared account or background sync. AirDrop/Files use the operating system's existing transfer tools. No Bluetooth permissions are required.

## Transfer the rendered sound into Serum

1. In the Mac companion, choose the preview note and **Note length**.
2. Click **Render WAV**. Rendering uses a separate SoundCore engine, includes the app's effects and adds a release/delay tail.
3. Drag **Drag WAV into Serum** into a Serum sample oscillator or Finder. Alternatively choose **Save WAV…**, then import that audio in Serum.

The output is stereo, 48 kHz, 16-bit PCM WAV. Effects are baked into the recorded audio; the original oscillator, modulation and effect controls are not editable in Serum. The bounded tail ends with a short fade. Set the sample's root pitch to the render note and choose Serum's desired sample pitch-tracking behavior. Playing other notes can change its rate and duration.

**Save recipe** writes the app parameters, asset metadata and routes as text for manual rebuilding. Different engine algorithms and parameter scales prevent those numbers from establishing an equivalent Serum patch. **Save .sdpatch** preserves the editable app sound.

## Build and verify

After a source update, close the existing Xcode project, run `xcodegen generate`, reopen `SoundDihsign.xcodeproj` and select your signing team. Build **SoundDihsign** for iOS 17+ or **SoundDihsignCompanion** for macOS 14+.

Portable C++ and shared Swift Foundation library tests passed on Linux. UIKit, SwiftUI and AVFoundation app builds, device playback, sandbox grants, AirDrop, native file pickers/exporters and drag/drop into Serum still need a Mac/iPhone test. See [validation results and acceptance checks](VALIDATION.md).
