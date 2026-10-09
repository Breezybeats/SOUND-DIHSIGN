#include "SerumPreset.h"
#include "SoundCore.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <memory>
#include <string>
#include <vector>
#include <zlib.h>

namespace {
using Bytes = std::vector<unsigned char>;
using Preset = std::unique_ptr<SD_Preset, decltype(&sd_preset_destroy)>;
int assertions = 0, failures = 0, scenarios = 0;
void check(bool condition, const char *message) {
    ++assertions;
    if (!condition) { ++failures; std::cerr << "FAIL: " << message << '\n'; }
}
void scenario(const char *name) { ++scenarios; std::cout << "CHECK " << name << '\n'; }
void be(Bytes &data, size_t offset, uint32_t value) {
    data[offset] = static_cast<unsigned char>(value >> 24);
    data[offset + 1] = static_cast<unsigned char>(value >> 16);
    data[offset + 2] = static_cast<unsigned char>(value >> 8);
    data[offset + 3] = static_cast<unsigned char>(value);
}
void le(Bytes &data, size_t offset, uint32_t value) {
    data[offset] = static_cast<unsigned char>(value);
    data[offset + 1] = static_cast<unsigned char>(value >> 8);
    data[offset + 2] = static_cast<unsigned char>(value >> 16);
    data[offset + 3] = static_cast<unsigned char>(value >> 24);
}
uint32_t readLE(const unsigned char *p) {
    return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24;
}
void f32(Bytes &data, size_t offset, float value) {
    uint32_t bits = 0; std::memcpy(&bits, &value, 4); le(data, offset, bits);
}
size_t paramOffset(int index) {
    return index < 228 ? 0x3460 + static_cast<size_t>(index) * 4
                      : 0x4AE0 + static_cast<size_t>(index - 228) * 4;
}
int countForSize(size_t size) { return size == 172736 ? 299 : size == 28232 ? 273 : 260; }
Bytes syntheticState(size_t size = 21808) {
    Bytes state(size, 0);
    const int count = countForSize(size);
    for (int i = 0; i < count; ++i) f32(state, paramOffset(i), .5f);
    f32(state, paramOffset(0), .75f);
    f32(state, paramOffset(1), .5f);
    f32(state, paramOffset(3), .25f); // -2 octaves.
    f32(state, paramOffset(4), .75f); // +6 semitones, independent octave.
    f32(state, paramOffset(5), .25f); // -50 cents.
    f32(state, paramOffset(6), .2f);  // Four voices.
    f32(state, paramOffset(14), .25f);
    f32(state, paramOffset(212), 1);
    f32(state, paramOffset(213), 1);
    f32(state, paramOffset(214), 0);
    f32(state, paramOffset(215), 1);
    f32(state, paramOffset(216), 1);
    for (int slot = 0; slot < 32; ++slot) {
        const size_t offset = slot < 16 ? static_cast<size_t>(slot) * 40 : 0x50E0 + static_cast<size_t>(slot - 16) * 40;
        state[offset + 33] = 0x80;
        state[offset + 34] = static_cast<unsigned char>(slot);
        state[offset + 35] = 0xFF;
        f32(state, offset + 8, 1);
    }
    const size_t flags = size == 172736 ? 0xB1E0 : 0x1AF4;
    state[flags + (size == 172736 ? 1 : 4)] = 1;
    const char *name = "Original synthetic patch";
    std::copy(name, name + std::strlen(name), state.begin() + 0x4972);
    const char *author = "Portable tests";
    std::copy(author, author + std::strlen(author), state.begin() + 0x49A0);
    const char *table = "Original test table";
    std::copy(table, table + std::strlen(table), state.begin() + 0x3C08);
    std::copy(table, table + std::strlen(table), state.begin() + 0x3E08);
    return state;
}
Bytes compress(const Bytes &input) {
    uLongf size = compressBound(input.size()); Bytes result(size);
    const unsigned char zero = 0;
    check(compress2(result.data(), &size, input.empty() ? &zero : input.data(), input.size(), 6) == Z_OK,
          "Synthetic compression succeeds");
    result.resize(size); return result;
}
Bytes makeFile(const Bytes &state, const Bytes &bank = {}, bool fullSize = true) {
    const auto a = compress(state), b = compress(bank);
    Bytes data(64 + a.size() + b.size());
    std::memcpy(data.data(), "CcnK", 4); std::memcpy(data.data() + 8, "FPCh", 4);
    std::memcpy(data.data() + 16, "XfsX", 4);
    be(data, 4, static_cast<uint32_t>(data.size() - (fullSize ? 0 : 8)));
    be(data, 12, 1); be(data, 20, 1); be(data, 24, 1);
    std::memcpy(data.data() + 28, "Synthetic program", 17);
    be(data, 56, static_cast<uint32_t>(data.size() - 60));
    std::copy(a.begin(), a.end(), data.begin() + 60);
    std::copy(b.begin(), b.end(), data.begin() + 60 + static_cast<ptrdiff_t>(a.size()));
    le(data, data.size() - 4, static_cast<uint32_t>(a.size()));
    return data;
}
Preset parse(const Bytes &data, std::string *error = nullptr) {
    std::array<char, 200> buffer{};
    Preset result(sd_preset_parse(data.data(), static_cast<int>(data.size()), buffer.data(), static_cast<int>(buffer.size())), sd_preset_destroy);
    if (error) *error = buffer.data();
    return result;
}
float mapped(const Preset &preset, int id) {
    float value = -999; check(sd_preset_mapped_parameter(preset.get(), id, &value) == 1, "Mapped parameter exists"); return value;
}
Bytes inflatePart(const Bytes &file, bool bank) {
    const size_t a = readLE(file.data() + file.size() - 4);
    const size_t start = bank ? 60 + a : 60, count = bank ? file.size() - 64 - a : a;
    Bytes result(8 * 1024 * 1024);
    uLongf length = result.size();
    check(uncompress(result.data(), &length, file.data() + start, count) == Z_OK, "Roundtrip compressed section can be read");
    result.resize(length); return result;
}
std::vector<float> rawValues(const Preset &preset) {
    const int count = sd_preset_raw_count(preset.get()); std::vector<float> values(static_cast<size_t>(count));
    for (int i = 0; i < count; ++i) check(sd_preset_raw_parameter(preset.get(), i, &values[i]) == 1, "Raw knob retained");
    return values;
}
Bytes rewrite(const Preset &preset, const std::vector<float> &values) {
    const int size = sd_preset_write_fxp(preset.get(), values.data(), static_cast<int>(values.size()), nullptr, 0);
    check(size > 0, "FXP rewrite computes a bounded length");
    if (size <= 0) return {};
    Bytes result(static_cast<size_t>(size));
    check(sd_preset_write_fxp(preset.get(), values.data(), static_cast<int>(values.size()), result.data(), size) == size,
          "FXP rewrite writes the whole file");
    return result;
}
void near(float actual, float expected, const char *message) { check(std::abs(actual - expected) < 1e-5f, message); }
void runSyntheticTests() {
    scenario("Known state layouts and normalized controls");
    for (size_t size : {21524u, 21804u, 21808u, 28232u, 172736u}) {
        auto preset = parse(makeFile(syntheticState(size)));
        check(bool(preset), "Verified schema imports"); if (!preset) continue;
        check(sd_preset_raw_count(preset.get()) == countForSize(size), "Schema has the verified raw knob count");
        check(std::string(sd_preset_name(preset.get())) == "Original synthetic patch", "State name retained");
        check(std::string(sd_preset_author(preset.get())) == "Portable tests", "State author retained");
        near(mapped(preset, SD_MASTER), .421875f, "Master uses the verified cubic amplitude curve");
        near(mapped(preset, SD_OSC_LEVEL), .25f, "Oscillator level uses square amplitude curve");
        near(mapped(preset, SD_OSC_OCTAVE), -2, "Octave maps separately");
        near(mapped(preset, SD_OSC_SEMITONES), 6, "Semitone maps separately");
        near(mapped(preset, SD_OSC_FINE), -50, "Fine cents map separately");
        near(mapped(preset, SD_OSC_UNISON), 4, "Unison count maps to four");
        near(mapped(preset, SD_ATTACK), 1, "Envelope nonlinear seconds are decoded");
        near(mapped(preset, SD_SUSTAIN), .25f, "Envelope sustain amplitude is decoded");
        near(mapped(preset, SD_LFO_RATE), 6.25f, "Free LFO rate curve is decoded");
        check(std::string(sd_preset_warnings(preset.get())).find("external wavetable") != std::string::npos,
              "Missing external tables are explicitly reported");
    }
    scenario("FXP file length convention");
    check(bool(parse(makeFile(syntheticState(), {}, false))), "VST spec length minus eight also imports");

    scenario("Embedded tables, opaque noise data and table full scale");
    auto state = syntheticState(); Bytes bank(8192 + 7, 0);
    le(state, 0x4968, 8192); f32(bank, 0, .75f); f32(bank, 4, 1.05f);
    for (size_t i = 8192; i < bank.size(); ++i) bank[i] = static_cast<unsigned char>(i - 8000);
    auto preset = parse(makeFile(state, bank)); check(bool(preset), "Table with opaque trailing noise imports");
    if (preset) {
        int count = -1, frame = -1; const float *table = sd_preset_oscillator_table(preset.get(), 0, &count, &frame);
        check(table && count == 2048 && frame == 2048, "Table dimensions are exact");
        if (table) { near(table[0], .75f, "Float sample is retained"); near(table[1], 1, "Preview full scale is bounded"); }
        check(std::string(sd_preset_warnings(preset.get())).find("noise/sample") != std::string::npos, "Extra noise bytes are reported");
        check(std::string(sd_preset_warnings(preset.get())).find("clipped") != std::string::npos, "Preview clipping is reported");
        auto values = rawValues(preset); const Bytes output = rewrite(preset, values);
        check(inflatePart(output, true) == bank, "Rewritten FXP retains every table and opaque noise byte");
    }

    scenario("Unipolar and bipolar LFO routes prevent zero-level silence");
    for (int type : {0, 1}) {
        auto routed = syntheticState(); f32(routed, paramOffset(1), 0);
        if (type == 1) f32(routed, paramOffset(1), .5f);
        f32(routed, 4, 1); routed[12] = static_cast<unsigned char>(type); routed[20] = 5; routed[26] = 1;
        auto item = parse(makeFile(routed)); check(bool(item), "Supported LFO route imports"); if (!item) continue;
        check(sd_preset_route_count(item.get()) == 1, "One supported route is retained");
        int source = 0, destination = 0; float amount = 0;
        check(sd_preset_route(item.get(), 0, &source, &destination, &amount) == 1, "Route can be read");
        check(source == SD_SOURCE_LFO1 && destination == SD_OSC_LEVEL, "LFO source and level destination are correct");
        near(mapped(item, SD_OSC_LEVEL), .5f, "LFO range is centered for a bipolar sine");
        near(amount, .5f, "Half-span amount covers the supported amplitude endpoints");
    }

    scenario("Envelope and velocity route polarity");
    auto routed = syntheticState(); f32(routed, 4, .5f); routed[12] = 1; routed[20] = 13; routed[26] = 2;
    auto velocity = parse(makeFile(routed)); check(bool(velocity), "Velocity route imports");
    if (velocity) { near(mapped(velocity, SD_OSC_PAN), .25f, "Bipolar velocity range offsets the base"); }

    scenario("Unknown sources and auxiliary routings are retained only in export");
    routed = syntheticState(); f32(routed, 4, 1); routed[20] = 6; routed[26] = 1;
    auto unknown = parse(makeFile(routed)); check(bool(unknown), "Unsupported modulation does not reject a valid preset");
    if (unknown) { check(sd_preset_route_count(unknown.get()) == 0, "Unsupported source is not aliased");
        check(std::string(sd_preset_warnings(unknown.get())).find("Unsupported modulation") != std::string::npos, "Unsupported route is reported"); }

    scenario("Tempo LFO follows verified subdivision table at 120 BPM");
    for (size_t size : {21808u, 172736u}) {
        auto tempo = syntheticState(size); const size_t flags = size == 172736 ? 0xB1E0 : 0x1AF4;
        tempo[flags + (size == 172736 ? 1 : 4)] = 0; f32(tempo, paramOffset(61), .5f);
        auto item = parse(makeFile(tempo)); check(bool(item), "Tempo preset imports");
        if (item) near(mapped(item, SD_LFO_RATE), 2, "Default quarter note is two Hz at 120 BPM");
    }

    scenario("Every raw knob changes and all non-knob state bytes survive rewrite");
    state = syntheticState(); preset = parse(makeFile(state)); check(bool(preset), "Base imports");
    if (preset) {
        auto values = rawValues(preset);
        for (size_t i = 0; i < values.size(); ++i) values[i] = static_cast<float>(i % 17) / 16;
        auto expected = state; for (size_t i = 0; i < values.size(); ++i) f32(expected, paramOffset(static_cast<int>(i)), values[i]);
        const auto output = rewrite(preset, values); auto imported = parse(output);
        check(bool(imported), "Every-knob FXP rewrite reparses");
        check(inflatePart(output, false) == expected, "Only verified knob bytes changed in the inflated state");
        if (imported) for (size_t i = 0; i < values.size(); ++i) { float value = -1;
            check(sd_preset_raw_parameter(imported.get(), static_cast<int>(i), &value) == 1 && value == values[i], "Every rewritten knob value matches exactly"); }
    }

    scenario("Rewrite validation leaves caller output untouched");
    if (preset) {
        auto values = rawValues(preset); Bytes untouched(32, 0xA5), output = untouched;
        check(sd_preset_write_fxp(preset.get(), values.data(), static_cast<int>(values.size()), output.data(), output.size()) == -1 && output == untouched,
              "Too-small output remains untouched");
        values[12] = std::numeric_limits<float>::quiet_NaN();
        check(sd_preset_write_fxp(preset.get(), values.data(), static_cast<int>(values.size()), output.data(), output.size()) == -1 && output == untouched,
              "Invalid knob values leave output untouched");
        check(sd_preset_write_fxp(preset.get(), values.data(), static_cast<int>(values.size()) - 1, nullptr, 0) == -1,
              "Cross-schema raw count is rejected");
    }

    scenario("Plugin/container identity and integrity errors");
    const auto valid = makeFile(syntheticState());
    for (size_t offset : {0u, 4u, 8u, 12u, 16u, 20u, 24u, 56u, 60u}) {
        auto corrupt = valid; corrupt[offset] ^= 0x40; std::string error;
        check(!parse(corrupt, &error) && !error.empty(), "Corrupt header or compression produces an error");
    }
    auto corrupt = valid; corrupt.resize(corrupt.size() - 1); check(!parse(corrupt), "Truncated file is rejected");
    corrupt = valid; le(corrupt, corrupt.size() - 4, 0xFFFFFFFF); check(!parse(corrupt), "Invalid compressed section size is rejected");
    check(!parse(makeFile(Bytes(22000, 0))), "Unknown state schema is rejected");

    scenario("Nonfinite/out-of-range controls and malformed records");
    for (float invalid : {-1.0f, 1.01f, std::numeric_limits<float>::infinity(), std::numeric_limits<float>::quiet_NaN()}) {
        auto malformed = syntheticState(); f32(malformed, paramOffset(240), invalid);
        check(!parse(makeFile(malformed)), "Invalid extended normalized knob is rejected");
    }
    state = syntheticState(); state[33] = 0; check(!parse(makeFile(state)), "Unknown matrix layout is rejected");
    state = syntheticState(); state[0x1AF8] = 9; check(!parse(makeFile(state)), "Unknown LFO flag schema is rejected");

    scenario("Wavetable bounds and nonfinite samples");
    state = syntheticState(); le(state, 0x4968, 8191); check(!parse(makeFile(state, Bytes(8192, 0))), "Incomplete wavetable frame is rejected");
    le(state, 0x4968, 8192); check(!parse(makeFile(state, Bytes(8191, 0))), "Truncated wavetable is rejected");
    bank = Bytes(8192, 0); f32(bank, 0, std::numeric_limits<float>::quiet_NaN()); check(!parse(makeFile(state, bank)), "Nonfinite wavetable is rejected");
    le(state, 0x4968, 2048 * 257 * 4); check(!parse(makeFile(state)), "Too many wavetable frames are rejected");

    scenario("Decompression bound");
    state = syntheticState(); check(!parse(makeFile(state, Bytes(8 * 1024 * 1024, 0))), "Combined inflated state and assets cannot exceed eight MiB");

    scenario("Null API arguments and safe error buffer termination");
    char error[2] = {'X', 'Y'};
    check(!sd_preset_parse(nullptr, 100, error, 2) && error[1] == '\0', "Tiny error buffer is terminated");
    check(sd_preset_raw_count(nullptr) == 0 && sd_preset_route_count(nullptr) == 0, "Null preset counts are safe");
    check(sd_preset_mapped_parameter(nullptr, 1, nullptr) == 0 && sd_preset_raw_parameter(nullptr, 0, nullptr) == 0, "Null value APIs are safe");
    int tableCount = 9, frameSize = 9;
    check(!sd_preset_oscillator_table(nullptr, 0, &tableCount, &frameSize) && tableCount == 0 && frameSize == 0,
          "Missing table clears output dimensions");
    check(sd_preset_write_fxp(nullptr, nullptr, 0, nullptr, 0) == -1, "Null rewrite fails safely");
}
void runPrivateFixture(const std::filesystem::path &path) {
    std::ifstream file(path, std::ios::binary);
    Bytes bytes((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    std::string error; auto preset = parse(bytes, &error);
    if (!preset) { std::cerr << "FIXTURE " << path.filename().string() << ": " << error << '\n'; check(false, "Private Serum fixture imports"); return; }
    check(true, "Private Serum fixture imports");
    auto values = rawValues(preset); const auto rewritten = rewrite(preset, values);
    check(inflatePart(bytes, false) == inflatePart(rewritten, false), "Real fixture original state survives unchanged rewrite");
    check(inflatePart(bytes, true) == inflatePart(rewritten, true), "Real fixture original asset/noise bytes survive unchanged rewrite");
    check(bool(parse(rewritten)), "Real fixture rewritten file reparses");
}
} // namespace

int main(int argc, char **argv) {
    runSyntheticTests();
    for (int i = 1; i < argc; ++i) {
        std::filesystem::path path(argv[i]);
        if (std::filesystem::is_directory(path)) {
            scenario("Private original Serum FXP fixture roundtrips");
            int files = 0;
            for (const auto &entry : std::filesystem::recursive_directory_iterator(path))
                if (entry.is_regular_file() && entry.path().extension() == ".fxp") { runPrivateFixture(entry.path()); ++files; }
            std::cout << "Private fixtures checked: " << files << '\n';
        } else { scenario("Private Serum fixture"); runPrivateFixture(path); }
    }
    std::cout << "Serum preset tests: " << scenarios << " scenarios, " << assertions << " assertions, " << failures << " failures\n";
    return failures ? 1 : 0;
}
