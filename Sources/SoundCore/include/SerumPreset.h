#ifndef SD_SERUM_PRESET_H
#define SD_SERUM_PRESET_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SD_Preset SD_Preset;

/* Offline, bounded reader for independently verified Serum 1 FXP schemas.
 * Input <=32 MiB; total inflated data <=8 MiB. Unknown schemas/plugin IDs,
 * corrupt streams and invalid normalized parameters fail with a short error.
 * Ownership of data remains with the caller; the result copies everything.
 * This is a partial translation to SoundCore, not Serum-compatible playback.
 */
SD_Preset *sd_preset_parse(const unsigned char *data, int byte_count,
                           char *error_buffer, int error_capacity);
void sd_preset_destroy(SD_Preset *preset);

/* Returned strings/pointers remain valid until sd_preset_destroy. */
const char *sd_preset_name(const SD_Preset *preset);
const char *sd_preset_author(const SD_Preset *preset);
const char *sd_preset_warnings(const SD_Preset *preset);

/* Only controls with an understood translation are present. Returns 1 on
 * success, 0 for absent/invalid IDs. Discrete values and limits follow
 * SoundCore.h. Raw values retain every normalized knob in the known schema.
 */
int sd_preset_mapped_parameter(const SD_Preset *preset, int parameter,
                                float *value);
int sd_preset_raw_count(const SD_Preset *preset);
int sd_preset_raw_parameter(const SD_Preset *preset, int index, float *value);

/* Oscillators A/B are 0/1. A missing external table returns null/count 0;
 * callers must not silently replace it with a different factory table.
 * A nonempty result contains decoded floats, 2048/frame, clamped to -1..1
 * for the app preview. The writer retains the original asset bytes.
 */
const float *sd_preset_oscillator_table(const SD_Preset *preset, int oscillator,
                                        int *sample_count, int *frame_size);
const char *sd_preset_oscillator_table_name(const SD_Preset *preset,
                                            int oscillator);

/* Translated supported routes, at most 16. Serum's custom LFO shape, curves,
 * timing and nonlinear responses are approximated and reported in warnings.
 * Source and destination use SoundCore IDs; amount is -1..1.
 */
int sd_preset_route_count(const SD_Preset *preset);
int sd_preset_route(const SD_Preset *preset, int index, int *source,
                      int *destination, float *amount);

/* Experimental offline FXP rewrite: change every known normalized parameter
 * while retaining the base preset's original routing, assets, extra noise
 * data, effect order and metadata. raw_count must exactly match raw_count().
 * The container is checked by independent roundtrip tests; playback/loading
 * in Serum still requires validation in Serum itself.
 * Returns required byte count when output is null/capacity 0; otherwise writes
 * the complete file and returns its length, or -1 without changing output on
 * invalid values, insufficient capacity or allocation/compression failure.
 */
int sd_preset_write_fxp(const SD_Preset *preset, const float *raw_values,
                         int raw_count, unsigned char *output,
                         int output_capacity);

#ifdef __cplusplus
}
#endif
#endif
