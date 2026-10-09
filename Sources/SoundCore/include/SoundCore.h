#ifndef SOUND_CORE_H
#define SOUND_CORE_H

/* SwiftPM uses this file as SoundCore's umbrella header. Export the preset
 * interface here so Swift's import SoundCore sees both public C APIs. */
#include "SerumPreset.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SD_Engine SD_Engine;

enum {
    SD_OSC_MODE = 0, SD_OSC_TABLE = 1, SD_OSC_POSITION = 2,
    SD_OSC_LEVEL = 3, SD_OSC_SEMITONES = 4, SD_OSC_FINE = 5,
    SD_OSC_UNISON = 6, SD_OSC_DETUNE = 7, SD_OSC_PAN = 8,
    SD_OSC_WARP = 9, SD_OSC_SCAN = 10, SD_OSC_GRAIN_SIZE = 11,
    SD_OSC_DENSITY = 12, SD_OSC_OCTAVE = 13,
    SD_CUTOFF = 128, SD_RESONANCE = 129, SD_DRIVE = 130,
    SD_DELAY = 131, SD_LFO_RATE = 132, SD_MASTER = 133,
    SD_ATTACK = 134, SD_DECAY = 135, SD_SUSTAIN = 136,
    SD_RELEASE = 137, SD_SUB_LEVEL = 138, SD_NOISE_LEVEL = 139,
    SD_MACRO1 = 140
};

enum {
    SD_MODE_WAVETABLE = 0, SD_MODE_SAMPLE = 1,
    SD_MODE_GRANULAR = 2, SD_MODE_SPECTRAL = 3
};

enum {
    SD_SOURCE_DISABLED = 0, SD_SOURCE_LFO1 = 1,
    SD_SOURCE_ENV1 = 2, SD_SOURCE_VELOCITY = 3, SD_SOURCE_MACRO1 = 4
};

/* Three oscillators: parameter ID = oscillator * 32 + SD_OSC_*.
 * Controls are 0..1 unless specified here: MODE 0..3, TABLE 0..2,
 * SEMITONES -24..24, OCTAVE -4..4 integer (independent of SEMITONES),
 * FINE -100..100 cents, UNISON 1..4,
 * CUTOFF 20..20000 Hz, LFO_RATE .05..20 Hz,
 * ATTACK/DECAY/RELEASE .001..5 seconds, GRAIN_SIZE .01.. .25 seconds,
 * DENSITY 1..60 grains/second. PAN 0=left, .5=center, 1=right.
 * Spectral mode is additive harmonic resynthesis, not Serum's FFT engine.
 */
SD_Engine *sd_create(double sample_rate);
void sd_destroy(SD_Engine *engine);
void sd_set_parameter(SD_Engine *engine, int parameter, float value);

/* Note events have one producer; render has one consumer. Queue overflow
 * requests a voice reset to prevent stuck notes. Parameter and matrix writes
 * may occur concurrently with rendering. Never destroy during rendering.
 */
void sd_note_on(SD_Engine *engine, int midi_note, float velocity);
void sd_note_off(SD_Engine *engine, int midi_note);
void sd_all_notes_off(SD_Engine *engine);

/* 16 slots. amount -1..1 spans the destination's normalized range.
 * LFO1 is bipolar; ENV1, velocity and MACRO1 are unipolar.
 * All continuous controls can be destinations; MODE/TABLE/UNISON/OCTAVE cannot.
 * Frequency and time destination ranges use logarithmic normalization.
 * Macro destinations are resolved once before macro sources, without recursion.
 */
void sd_set_modulation(SD_Engine *engine, int slot, int source,
                       int destination, float amount);

/* Render allocates no memory and takes no locks. Buffers must be distinct,
 * valid arrays of frames floats. Invalid engine produces silence.
 */
void sd_render(SD_Engine *engine, float *left, float *right, int frames);

/* Call only while rendering is stopped. Copies a mono one-shot, up to ten
 * seconds at 8..192 kHz; returns 1 on success, 0 on invalid input/failure.
 * Input is sanitized and bounded; caller retains ownership of input.
 * Imported samples also supply spectral mode's harmonic analysis.
 */
int sd_load_sample(SD_Engine *engine, int oscillator, const float *mono,
                   int frames, double source_sample_rate);

/* Stop-only wavetable import. frame_size must be a power of two, 32..2048;
 * sample_count must contain 1..256 complete frames. Builds harmonic mip levels
 * offline and interpolates POSITION between frames during playback. Imported
 * data supplies wavetable and spectral modes for that oscillator. Pass nullptr,
 * 0, 0 to restore built-in tables. Returns 1 on success, 0 on failure.
 */
int sd_load_wavetable(SD_Engine *engine, int oscillator, const float *samples,
                      int sample_count, int frame_size);

/* Offline original wavetable generation; no engine is required. Caller owns
 * sample_count writable floats. frame_size must be a power of two, 32..2048;
 * sample_count must contain 2..256 complete frames. Additive bass/formant
 * spectra morph smoothly across frames with fixed harmonic phases, zero DC,
 * and one shared peak normalization <= .95. Harmonics stay below Nyquist.
 * xorshift32 uses shifts 13/17/5; seed 0 maps to 0x9e3779b9. Repeating a seed
 * and dimensions repeats the generated bank. Run off the audio/UI thread.
 * Returns 1 on success; invalid input/allocation failure returns 0 without
 * changing output. Load a successful bank with sd_load_wavetable while stopped.
 */
int sd_generate_wavetable(float *output, int sample_count, int frame_size,
                          unsigned int seed);

#ifdef __cplusplus
}
#endif
#endif
