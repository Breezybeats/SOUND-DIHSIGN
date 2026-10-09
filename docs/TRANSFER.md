# iPhone → macOS → Serum

The macOS companion receives SOUND DIHSIGN patches, previews them with the same
shared synthesis engine, and renders audio for the studio. It does not host Serum
or create native Serum preset files.

## Transfer an editable SOUND DIHSIGN patch

1. Export a `.sdpatch` from the iPhone app using its share/export control.
2. Send the file to your Mac with AirDrop, or save it in Files and move it to the
   Mac through your usual file service or a cable.
3. In **SOUND DIHSIGN Companion**, click **Import patch**, or drop the local file
   on its window. Select the imported patch in the library.
4. Choose a note and click **Play preview**. **Stop / Panic** or **⌘.** stops all
notes. The preview holds the note until stopped; a one-shot sample can finish sooner.

The desktop stores a validated copy in its Application Support directory. In a
sandboxed build, this is within the application's container, under
`Library/Application Support/SOUND-DIHSIGN/Library`. Imported originals stay
untouched. Removing a library entry removes only the companion's copy. Samples,
custom wavetables, parameter values, and modulation routes travel inside the
`.sdpatch`; imports and exports share a 32 MiB file limit. Asset limits are checked
by the shared schema before audio playback.

There is no automatic wireless pairing, server, shared account, or background
sync in this version. AirDrop/Files transfer uses the operating system's existing
tools. No Bluetooth permissions are needed.

## Transfer the rendered sound into Serum

1. Choose the preview note and **Note length**.
2. Click **Render WAV**. Rendering uses a separate engine, includes SOUND DIHSIGN's
   effects, and adds a release/delay tail.
3. Drag **Drag WAV into Serum** into Serum's sample oscillator or into Finder.
   Alternatively, choose **Save WAV…**, then import that saved audio in Serum.

The output is stereo, 48 kHz, 16-bit PCM WAV. It is a rendered one-shot: effects
are baked into audio, and the original oscillator settings and modulation are
not editable in Serum. The bounded release/delay tail ends with a short fade to
avoid an abrupt cutoff. Notes played above or below the render's base note can
change playback rate and duration according to Serum's sample settings. Set its
root pitch to the note used for the render; consult Serum's sample oscillator
controls for the desired pitch tracking behavior.

**Save recipe** writes a plain-text list of the app's parameters, embedded asset
metadata, and modulation routes. It is a starting point for rebuilding a patch
manually in Serum. The engines' oscillator algorithms, scales, modulation, and
effects differ, so numeric values do not establish an equivalent Serum patch.
**Save .sdpatch** preserves the editable SOUND DIHSIGN patch for reuse in either
app.

## Native Serum preset export

Native SerumPreset export is unavailable. This project has no documented Serum 2
writer, compatibility mapping, or round-trip validation in Serum. Renaming a
`.sdpatch` or WAV to a Serum preset extension will not convert it. A future native
exporter would require a supported format/API or a verified implementation, an
explicit feature mapping, and audible comparison in Serum on macOS before making
compatibility promises.

## Build and verification

Generate the Xcode project with the repository's `project.yml`, then build/run the
`SoundDihsignCompanion` scheme on macOS 14 or newer. The companion uses SwiftUI,
AVAudioEngine, the shared patch schema, and the C++ SoundCore package. Its sandbox
entitlement permits only user-selected file access plus its app container.

Native macOS build, audio-device playback, sandbox file grants, and drag/drop into
Serum must be checked in Xcode on a Mac. Linux cannot run these Apple frameworks.
Useful manual checks are: import an iPhone patch with a sample and custom table,
audition all four oscillator modes, stop sustained notes, render/open a WAV,
save/reimport a `.sdpatch`, reject malformed/oversized imports, and reopen the
app to confirm the library persists.
