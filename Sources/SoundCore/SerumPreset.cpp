#include "SerumPreset.h"
#include "SoundCore.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#include <zlib.h>

namespace {
constexpr size_t kInputLimit = 32 * 1024 * 1024;
constexpr size_t kInflatedLimit = 8 * 1024 * 1024;
constexpr size_t kPrimaryOffset = 0x3460;
constexpr size_t kExtendedOffset = 0x4AE0;
constexpr int kPrimaryCount = 228;
constexpr int kFrameSize = 2048;
constexpr size_t kTableByteLimit = kFrameSize * 256 * sizeof(float);
using Bytes = std::vector<unsigned char>;
struct Route { int source; int destination; float amount; };

uint32_t be32(const unsigned char *p) {
    return uint32_t(p[0]) << 24 | uint32_t(p[1]) << 16 |
           uint32_t(p[2]) << 8 | uint32_t(p[3]);
}
uint32_t le32(const unsigned char *p) {
    return uint32_t(p[0]) | uint32_t(p[1]) << 8 |
           uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24;
}
uint16_t le16(const unsigned char *p) { return uint16_t(p[0]) | uint16_t(p[1]) << 8; }
void putBE32(unsigned char *p, uint32_t n) {
    p[0] = static_cast<unsigned char>(n >> 24);
    p[1] = static_cast<unsigned char>(n >> 16);
    p[2] = static_cast<unsigned char>(n >> 8);
    p[3] = static_cast<unsigned char>(n);
}
void putLE32(unsigned char *p, uint32_t n) {
    p[0] = static_cast<unsigned char>(n);
    p[1] = static_cast<unsigned char>(n >> 8);
    p[2] = static_cast<unsigned char>(n >> 16);
    p[3] = static_cast<unsigned char>(n >> 24);
}
float readFloat(const unsigned char *p) {
    const uint32_t bits = le32(p);
    float value = 0;
    static_assert(sizeof(value) == sizeof(bits), "32-bit IEEE floats required");
    std::memcpy(&value, &bits, sizeof(value));
    return value;
}
void writeFloat(unsigned char *p, float value) {
    uint32_t bits = 0;
    std::memcpy(&bits, &value, sizeof(bits));
    putLE32(p, bits);
}
void require(bool condition, const char *message) {
    if (!condition) throw std::runtime_error(message);
}
void errorText(char *buffer, int capacity, const char *message) {
    if (!buffer || capacity <= 0) return;
    const size_t count = std::min(std::strlen(message), static_cast<size_t>(capacity - 1));
    std::memcpy(buffer, message, count);
    buffer[count] = '\0';
}
Bytes inflateExact(const unsigned char *input, size_t count, size_t limit) {
    z_stream stream{};
    require(inflateInit(&stream) == Z_OK, "Could not initialize preset decompression.");
    struct Guard { z_stream *stream; ~Guard() { inflateEnd(stream); } } guard{&stream};
    stream.next_in = const_cast<unsigned char *>(input);
    stream.avail_in = static_cast<uInt>(count);
    Bytes output;
    std::array<unsigned char, 32768> chunk{};
    int result = Z_OK;
    do {
        stream.next_out = chunk.data();
        stream.avail_out = static_cast<uInt>(chunk.size());
        result = inflate(&stream, Z_NO_FLUSH);
        require(result == Z_OK || result == Z_STREAM_END, "Preset compressed data is corrupt or truncated.");
        const size_t produced = chunk.size() - stream.avail_out;
        require(produced <= limit - output.size(), "Preset inflated data exceeds the 8 MiB limit.");
        output.insert(output.end(), chunk.begin(), chunk.begin() + static_cast<ptrdiff_t>(produced));
        require(result == Z_STREAM_END || produced || stream.avail_in,
                "Preset compressed data is truncated.");
    } while (result != Z_STREAM_END);
    require(stream.avail_in == 0, "Preset has unexpected bytes inside a compressed section.");
    return output;
}
Bytes deflateBytes(const Bytes &input) {
    uLongf size = compressBound(static_cast<uLong>(input.size()));
    Bytes output(static_cast<size_t>(size));
    const unsigned char empty = 0;
    require(compress2(output.data(), &size, input.empty() ? &empty : input.data(),
                     static_cast<uLong>(input.size()), Z_DEFAULT_COMPRESSION) == Z_OK,
            "Could not compress preset data.");
    output.resize(static_cast<size_t>(size));
    return output;
}
int schemaCount(size_t stateSize) {
    // These exact layouts were independently inspected in the user's files.
    // The FXP plugin version is always 1 and cannot identify a state schema.
    switch (stateSize) {
        case 21524: case 21804: case 21808: return 260;
        case 28232: return 273;
        case 172736: return 299;
        default: throw std::runtime_error("This Serum FXP state layout is not supported yet.");
    }
}
size_t rawOffset(int index) {
    return index < kPrimaryCount ? kPrimaryOffset + static_cast<size_t>(index) * 4
         : kExtendedOffset + static_cast<size_t>(index - kPrimaryCount) * 4;
}
std::string textAt(const Bytes &state, size_t offset, size_t limit) {
    std::string result;
    for (size_t i = offset; i < offset + limit && state[i]; ++i) {
        const unsigned char c = state[i];
        if (c >= 32 && c != 127) result.push_back(static_cast<char>(c));
    }
    return result;
}
float unit(float value) { return std::clamp(value, 0.0f, 1.0f); }
float normalized(int id, float value) {
    if (id == SD_CUTOFF) return std::log(value / 20.0f) / std::log(1000.0f);
    if (id == SD_LFO_RATE) return std::log(value / .05f) / std::log(400.0f);
    if (id == SD_ATTACK || id == SD_DECAY || id == SD_RELEASE)
        return std::log(value / .001f) / std::log(5000.0f);
    if (id < 96 && id % 32 == SD_OSC_FINE) return (value + 100) / 200;
    if (id < 96 && id % 32 == SD_OSC_SEMITONES) return (value + 24) / 48;
    return value;
}
float actual(int id, float value) {
    value = unit(value);
    if (id == SD_CUTOFF) return 20 * std::pow(1000.0f, value);
    if (id == SD_LFO_RATE) return .05f * std::pow(400.0f, value);
    if (id == SD_ATTACK || id == SD_DECAY || id == SD_RELEASE)
        return .001f * std::pow(5000.0f, value);
    if (id < 96 && id % 32 == SD_OSC_FINE) return value * 200 - 100;
    if (id < 96 && id % 32 == SD_OSC_SEMITONES) return value * 48 - 24;
    return value;
}
int nativeDestination(int raw) {
    if (raw == 0) return SD_MASTER;
    if (raw == 27) return SD_NOISE_LEVEL;
    if (raw == 33) return SD_SUB_LEVEL;
    if (raw == 35) return SD_ATTACK;
    if (raw == 37) return SD_DECAY;
    if (raw == 38) return SD_SUSTAIN;
    if (raw == 39) return SD_RELEASE;
    if (raw == 45) return SD_CUTOFF;
    if (raw == 46) return SD_RESONANCE;
    if (raw == 61) return SD_LFO_RATE;
    if (raw == 218) return SD_MACRO1;
    for (int osc = 0; osc < 2; ++osc) {
        const int index = raw - osc * 13;
        const int offset = osc * 32;
        if (index == 1) return offset + SD_OSC_LEVEL;
        if (index == 2) return offset + SD_OSC_PAN;
        if (index == 4) return offset + SD_OSC_SEMITONES;
        if (index == 5) return offset + SD_OSC_FINE;
        if (index == 7) return offset + SD_OSC_DETUNE;
        if (index == 11) return offset + SD_OSC_POSITION;
    }
    return -1;
}
float translate(int raw, float value) {
    const int id = nativeDestination(raw);
    value = unit(value);
    if (raw == 0) return value * value * value;
    if (raw == 1 || raw == 14 || raw == 27 || raw == 33 || raw == 38) return value * value;
    if (raw == 4 || raw == 17) return std::round(value * 24 - 12);
    if (raw == 5 || raw == 18) return value * 200 - 100;
    if (raw == 35 || raw == 37 || raw == 39)
        return std::clamp(32 * std::pow(value, 5.0f), .001f, 5.0f);
    if (raw == 45) return std::clamp(8 * std::pow(22050.0f / 8, value), 20.0f, 20000.0f);
    if (raw == 61) return std::clamp(100 * std::pow(value, 4.0f), .05f, 20.0f);
    return id >= 0 ? value : 0;
}
int nativeSource(int raw) {
    switch (raw) {
        case 5: return SD_SOURCE_LFO1;
        case 2: return SD_SOURCE_ENV1;
        case 13: return SD_SOURCE_VELOCITY;
        case 24: return SD_SOURCE_MACRO1;
        default: return SD_SOURCE_DISABLED;
    }
}
} // namespace

struct SD_Preset {
    std::array<unsigned char, 60> header{};
    bool fullFileSize = true;
    Bytes state, bank;
    std::string name, author, warnings;
    std::vector<std::string> warningList;
    std::vector<float> raw;
    std::array<float, 160> mapped{};
    std::array<bool, 160> present{};
    std::array<std::vector<float>, 2> tables;
    std::array<std::string, 2> tableNames;
    std::vector<Route> routes;

    void warn(const std::string &message) {
        if (std::find(warningList.begin(), warningList.end(), message) == warningList.end())
            warningList.push_back(message);
    }
    void set(int id, float value) { mapped[static_cast<size_t>(id)] = value; present[static_cast<size_t>(id)] = true; }
    void finishWarnings() {
        for (const auto &item : warningList) { if (!warnings.empty()) warnings += "\n"; warnings += item; }
    }
};

namespace {
void loadTables(SD_Preset &preset) {
    size_t position = 0;
    for (int osc = 0; osc < 2; ++osc) {
        const size_t count = le32(preset.state.data() + 0x4968 + osc * 4);
        require(count <= kTableByteLimit && count % (kFrameSize * 4) == 0,
                "Preset wavetable dimensions are invalid or exceed 256 frames.");
        require(count <= preset.bank.size() - position, "Preset wavetable data is truncated.");
        preset.tableNames[osc] = textAt(preset.state, 0x3C08 + osc * 512, 512);
        auto &table = preset.tables[osc];
        table.reserve(count / 4);
        for (size_t byte = 0; byte < count; byte += 4) {
            const float value = readFloat(preset.bank.data() + position + byte);
            require(std::isfinite(value), "Preset wavetable contains nonfinite samples.");
            if (std::abs(value) > 1) preset.warn("A wavetable exceeds full scale; phone preview samples are clipped, and FXP export retains the original data.");
            table.push_back(std::clamp(value, -1.0f, 1.0f));
        }
        if (!count && preset.raw[212 + osc] >= .5f)
            preset.warn(std::string("Oscillator ") + (osc ? "B" : "A") + " needs an external wavetable: " +
                        (preset.tableNames[osc].empty() ? "unnamed table" : preset.tableNames[osc]) + ". It is unavailable for phone preview.");
        position += count;
    }
    if (position < preset.bank.size())
        preset.warn("Embedded noise/sample data is retained for FXP export and is not rendered by the phone preview.");
}
void loadParameters(SD_Preset &preset) {
    for (int raw = 0; raw < static_cast<int>(preset.raw.size()); ++raw) {
        const int id = nativeDestination(raw);
        if (id >= 0) preset.set(id, translate(raw, preset.raw[raw]));
    }
    for (int osc = 0; osc < 2; ++osc) {
        const int offset = osc * 32, index = osc * 13;
        preset.set(offset + SD_OSC_MODE, SD_MODE_WAVETABLE);
        preset.set(offset + SD_OSC_OCTAVE, std::round(8 * preset.raw[index + 3] - 4));
        const float unison = 1 + std::round(15 * preset.raw[index + 6]);
        preset.set(offset + SD_OSC_UNISON, std::min(unison, 4.0f));
        if (unison > 4) preset.warn("Unison is capped at four voices per oscillator in phone preview.");
        if (preset.raw[212 + osc] < .5f) preset.set(offset + SD_OSC_LEVEL, 0);
        // A different algorithm is not a valid translation of Serum's warp.
        preset.set(offset + SD_OSC_WARP, 0);
    }
    preset.set(64 + SD_OSC_LEVEL, 0); // Serum 1 has two main oscillators.
    if (preset.raw[215] < .5f) preset.set(SD_SUB_LEVEL, 0);
    preset.set(SD_NOISE_LEVEL, 0); // Serum noise assets are not white-noise substitutes.
    if (preset.raw[214] >= .5f) preset.warn("The Serum noise oscillator is omitted from phone preview; its original settings/data remain in FXP export.");
    if (preset.raw[216] < .5f) { preset.set(SD_CUTOFF, 20000); preset.set(SD_RESONANCE, 0); }
    else preset.warn("Phone preview uses its low-pass filter; Serum's selected filter model is not reproduced.");
    preset.set(SD_DRIVE, 0);
    preset.set(SD_DELAY, 0);
    preset.warn("Phone preview does not reproduce Serum warp/FM algorithms, effect chains, custom LFO shapes or their timing exactly. FXP export retains the base preset's original structures.");
    preset.warn("Pitch/level settings are translated; detune, envelope response and cutoff are approximate, and times/frequencies are limited to phone preview ranges.");
    const size_t flags = preset.state.size() == 172736 ? 0xB1E0 : 0x1AF4;
    const size_t stride = preset.state.size() == 172736 ? 1 : 4;
    const unsigned char hz = preset.state[flags + stride];
    const unsigned char dotted = preset.state[flags + stride * 2];
    const unsigned char triplet = preset.state[flags + stride * 3];
    require(hz <= 1 && dotted <= 1 && triplet <= 1, "Preset LFO mode flags do not match the known schema.");
    if (!hz) {
        const int step = static_cast<int>(std::round(preset.raw[61] * 228));
        constexpr std::array<int, 14> ends{13,29,46,62,78,94,111,127,143,160,176,192,208,225};
        const int division = static_cast<int>(std::lower_bound(ends.begin(), ends.end(), step) - ends.begin());
        float rate = .015625f * std::pow(2.0f, static_cast<float>(division));
        if (dotted) rate *= 2.0f / 3;
        if (triplet) rate *= 1.5f;
        preset.set(SD_LFO_RATE, std::clamp(rate, .05f, 20.0f));
        preset.warn("Tempo-synced LFO 1 is previewed at 120 BPM using a sine shape.");
    }
}
size_t modulationOffset(const SD_Preset &preset, int slot) {
    // All 299 inspected files locate the latter sixteen records at 0x50E0.
    // Searching markers would mistake legacy tail bytes for extra routes.
    const size_t offset = slot < 16 ? static_cast<size_t>(slot) * 40
        : 0x50E0 + static_cast<size_t>(slot - 16) * 40;
    require(preset.state[offset + 33] == 0x80 && preset.state[offset + 34] == slot && preset.state[offset + 35] == 0xFF,
            "Preset modulation records do not match the known schema.");
    return offset;
}
void loadRoutes(SD_Preset &preset) {
    const auto originalMapped = preset.mapped;
    std::array<float, 160> offsets{};
    for (int slot = 0; slot < 32; ++slot) {
        const size_t offset = modulationOffset(preset, slot);
        const auto *record = preset.state.data() + offset;
        const int rawSource = le16(record + 20);
        if (rawSource == 0) continue;
        const int rawDestination = le16(record + 26);
        const int source = nativeSource(rawSource), destination = nativeDestination(rawDestination);
        const float amount = readFloat(record + 4), scale = readFloat(record + 8);
        require(std::isfinite(amount) && std::isfinite(scale) && std::abs(amount) <= 1 && std::abs(scale) <= 1,
                "Preset modulation amount is invalid.");
        const int type = record[12];
        if (source == SD_SOURCE_DISABLED || destination < 0 || rawDestination >= static_cast<int>(preset.raw.size()) ||
            type > 1 || le16(record + 22) != 0 || destination == SD_NOISE_LEVEL ||
            ((destination == SD_CUTOFF || destination == SD_RESONANCE) && preset.raw[216] < .5f) ||
            (destination == SD_SUB_LEVEL && preset.raw[215] < .5f) ||
            (destination < 64 && destination % 32 == SD_OSC_LEVEL && preset.raw[212 + destination / 32] < .5f)) {
            preset.warn("Unsupported modulation sources, destinations or auxiliary/curve modes are omitted from phone preview and retained in FXP export.");
            continue;
        }
        if (destination == SD_LFO_RATE) {
            preset.warn("LFO rate modulation is retained for FXP export and omitted from phone preview.");
            continue;
        }
        if (preset.routes.size() >= 16) { preset.warn("Phone preview supports sixteen modulation routes; remaining original routes are retained in FXP export."); continue; }
        const float depth = amount * scale;
        if (depth == 0) continue;
        const float base = preset.raw[rawDestination];
        const float low = base - (type == 1 ? depth * .5f : 0);
        const float high = base + (type == 1 ? depth * .5f : depth);
        const float start = normalized(destination, translate(rawDestination, low));
        const float end = normalized(destination, translate(rawDestination, high));
        const float original = normalized(destination, originalMapped[destination]);
        const bool bipolarSource = source == SD_SOURCE_LFO1;
        const float newBase = bipolarSource ? (start + end) * .5f : start;
        offsets[destination] += newBase - original;
        const float mappedAmount = std::clamp((end - start) * (bipolarSource ? .5f : 1.0f), -1.0f, 1.0f);
        if (mappedAmount != 0) preset.routes.push_back({source, destination, mappedAmount});
    }
    for (size_t id = 0; id < offsets.size(); ++id)
        if (offsets[id] != 0) preset.set(static_cast<int>(id), actual(static_cast<int>(id), normalized(static_cast<int>(id), originalMapped[id]) + offsets[id]));
    if (!preset.routes.empty()) preset.warn("Supported modulation is translated to phone preview ranges; nonlinear curves and the LFO waveform remain approximate.");
}
} // namespace

extern "C" SD_Preset *sd_preset_parse(const unsigned char *data, int byte_count, char *error_buffer, int error_capacity) {
    errorText(error_buffer, error_capacity, "");
    try {
        require(data && byte_count >= 76 && static_cast<size_t>(byte_count) <= kInputLimit,
                "Preset input must be a complete FXP file of at most 32 MiB.");
        const size_t count = static_cast<size_t>(byte_count);
        require(std::memcmp(data, "CcnK", 4) == 0 && std::memcmp(data + 8, "FPCh", 4) == 0 && std::memcmp(data + 16, "XfsX", 4) == 0,
                "This file is not a Serum 1 FXP preset.");
        require(be32(data + 12) == 1 && be32(data + 20) == 1 && be32(data + 24) == 1,
                "This FXP container version is not supported.");
        const uint32_t fileSize = be32(data + 4);
        require(fileSize == count || fileSize == count - 8, "Preset file length does not match its FXP header.");
        require(be32(data + 56) == count - 60, "Preset chunk length does not match its FXP header.");
        const size_t firstSize = le32(data + count - 4);
        require(firstSize >= 6 && firstSize <= count - 70, "Preset compression section lengths are invalid.");
        auto preset = std::make_unique<SD_Preset>();
        std::copy(data, data + 60, preset->header.begin());
        preset->fullFileSize = fileSize == count;
        preset->state = inflateExact(data + 60, firstSize, kInflatedLimit);
        const int rawCount = schemaCount(preset->state.size());
        preset->bank = inflateExact(data + 60 + firstSize, count - 64 - firstSize,
                                   kInflatedLimit - preset->state.size());
        preset->raw.reserve(static_cast<size_t>(rawCount));
        for (int i = 0; i < rawCount; ++i) {
            const float value = readFloat(preset->state.data() + rawOffset(i));
            require(std::isfinite(value) && value >= 0 && value <= 1,
                    "Preset contains invalid normalized knob values.");
            preset->raw.push_back(value);
        }
        preset->name = textAt(preset->state, 0x4972, 46);
        if (preset->name.empty()) preset->name.assign(reinterpret_cast<const char *>(data + 28),
            static_cast<size_t>(std::find(data + 28, data + 56, 0) - (data + 28)));
        if (preset->name.empty()) preset->name = "Imported Serum preset";
        preset->author = textAt(preset->state, 0x49A0, 48);
        loadTables(*preset);
        loadParameters(*preset);
        loadRoutes(*preset);
        preset->finishWarnings();
        return preset.release();
    } catch (const std::exception &error) { errorText(error_buffer, error_capacity, error.what()); }
      catch (...) { errorText(error_buffer, error_capacity, "Preset import failed."); }
    return nullptr;
}
extern "C" void sd_preset_destroy(SD_Preset *preset) { delete preset; }
extern "C" const char *sd_preset_name(const SD_Preset *preset) { return preset ? preset->name.c_str() : ""; }
extern "C" const char *sd_preset_author(const SD_Preset *preset) { return preset ? preset->author.c_str() : ""; }
extern "C" const char *sd_preset_warnings(const SD_Preset *preset) { return preset ? preset->warnings.c_str() : ""; }
extern "C" int sd_preset_mapped_parameter(const SD_Preset *preset, int parameter, float *value) {
    if (!preset || !value || parameter < 0 || parameter >= static_cast<int>(preset->mapped.size()) || !preset->present[parameter]) return 0;
    *value = preset->mapped[parameter]; return 1;
}
extern "C" int sd_preset_raw_count(const SD_Preset *preset) { return preset ? static_cast<int>(preset->raw.size()) : 0; }
extern "C" int sd_preset_raw_parameter(const SD_Preset *preset, int index, float *value) {
    if (!preset || !value || index < 0 || index >= static_cast<int>(preset->raw.size())) return 0;
    *value = preset->raw[index]; return 1;
}
extern "C" const float *sd_preset_oscillator_table(const SD_Preset *preset, int oscillator, int *sample_count, int *frame_size) {
    if (sample_count) *sample_count = 0;
    if (frame_size) *frame_size = 0;
    if (!preset || oscillator < 0 || oscillator >= 2 || preset->tables[oscillator].empty()) return nullptr;
    if (sample_count) *sample_count = static_cast<int>(preset->tables[oscillator].size());
    if (frame_size) *frame_size = kFrameSize;
    return preset->tables[oscillator].data();
}
extern "C" const char *sd_preset_oscillator_table_name(const SD_Preset *preset, int oscillator) {
    return preset && oscillator >= 0 && oscillator < 2 ? preset->tableNames[oscillator].c_str() : "";
}
extern "C" int sd_preset_route_count(const SD_Preset *preset) { return preset ? static_cast<int>(preset->routes.size()) : 0; }
extern "C" int sd_preset_route(const SD_Preset *preset, int index, int *source, int *destination, float *amount) {
    if (!preset || !source || !destination || !amount || index < 0 || index >= static_cast<int>(preset->routes.size())) return 0;
    const auto &route = preset->routes[index]; *source = route.source; *destination = route.destination; *amount = route.amount; return 1;
}
extern "C" int sd_preset_write_fxp(const SD_Preset *preset, const float *raw_values, int raw_count, unsigned char *output, int output_capacity) {
    try {
        require(preset && raw_values && raw_count == static_cast<int>(preset->raw.size()) && output_capacity >= 0,
                "Invalid preset rewrite arguments.");
        Bytes state = preset->state;
        for (int i = 0; i < raw_count; ++i) {
            require(std::isfinite(raw_values[i]) && raw_values[i] >= 0 && raw_values[i] <= 1,
                    "Invalid normalized parameter for preset rewrite.");
            writeFloat(state.data() + rawOffset(i), raw_values[i]);
        }
        const Bytes compressedState = deflateBytes(state), compressedBank = deflateBytes(preset->bank);
        const size_t size = 64 + compressedState.size() + compressedBank.size();
        require(size <= kInputLimit && size <= static_cast<size_t>(std::numeric_limits<int>::max()), "Rewritten preset exceeds the input limit.");
        if (!output || output_capacity == 0) return static_cast<int>(size);
        require(static_cast<size_t>(output_capacity) >= size, "Preset rewrite output buffer is too small.");
        Bytes file(size);
        std::copy(preset->header.begin(), preset->header.end(), file.begin());
        putBE32(file.data() + 4, static_cast<uint32_t>(size - (preset->fullFileSize ? 0 : 8)));
        putBE32(file.data() + 56, static_cast<uint32_t>(size - 60));
        std::copy(compressedState.begin(), compressedState.end(), file.begin() + 60);
        std::copy(compressedBank.begin(), compressedBank.end(), file.begin() + 60 + static_cast<ptrdiff_t>(compressedState.size()));
        putLE32(file.data() + size - 4, static_cast<uint32_t>(compressedState.size()));
        std::memcpy(output, file.data(), size);
        return static_cast<int>(size);
    } catch (...) { return -1; }
}
