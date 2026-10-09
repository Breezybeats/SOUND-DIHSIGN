#include "SoundCore.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <functional>
#include <iostream>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {
constexpr int kRate = 48000;
constexpr double kPi = 3.14159265358979323846;
using Engine = std::unique_ptr<SD_Engine, decltype(&sd_destroy)>;
int assertions = 0;
void require(bool condition, const char *message) {
    ++assertions;
    if (!condition) throw std::runtime_error(message);
}
Engine engine() {
    Engine e(sd_create(kRate), sd_destroy);
    require(e != nullptr, "engine creation failed");
    return e;
}
struct Audio { std::vector<float> left, right; };
Audio render(SD_Engine *e, int frames) {
    Audio audio{std::vector<float>(frames), std::vector<float>(frames)};
    for (int offset = 0; offset < frames; offset += 256) {
        const int count = std::min(256, frames - offset);
        sd_render(e, audio.left.data() + offset, audio.right.data() + offset, count);
    }
    return audio;
}
double rms(const std::vector<float> &samples, size_t start = 0) {
    double energy = 0;
    for (size_t i = start; i < samples.size(); ++i) energy += samples[i] * samples[i];
    return std::sqrt(energy / std::max<size_t>(1, samples.size() - start));
}
double difference(const std::vector<float> &a, const std::vector<float> &b) {
    double energy = 0;
    for (size_t i = 0; i < std::min(a.size(), b.size()); ++i) {
        const double d = a[i] - b[i]; energy += d * d;
    }
    return std::sqrt(energy / std::max<size_t>(1, std::min(a.size(), b.size())));
}
bool finiteBounded(const Audio &audio) {
    for (const auto *channel : {&audio.left, &audio.right})
        for (float value : *channel)
            if (!std::isfinite(value) || std::abs(value) > 1.0f) return false;
    return true;
}
double pitch(const std::vector<float> &audio) {
    int first = -1, last = -1, crossings = 0;
    for (size_t i = 4000; i < audio.size(); ++i) {
        if (audio[i - 1] <= 0 && audio[i] > 0) {
            if (first < 0) first = static_cast<int>(i);
            last = static_cast<int>(i); ++crossings;
        }
    }
    return crossings > 1 ? (crossings - 1.0) * kRate / (last - first) : 0;
}
Audio held(int mode, float position = .48f, float warp = .2f) {
    auto e = engine();
    sd_set_parameter(e.get(), SD_OSC_MODE, static_cast<float>(mode));
    sd_set_parameter(e.get(), SD_OSC_TABLE, 1);
    sd_set_parameter(e.get(), SD_OSC_POSITION, position);
    sd_set_parameter(e.get(), SD_OSC_WARP, warp);
    sd_note_on(e.get(), 60, .85f);
    return render(e.get(), kRate / 2);
}
void writeU16(std::ofstream &out, uint16_t value) {
    const char bytes[]{static_cast<char>(value), static_cast<char>(value >> 8)};
    out.write(bytes, 2);
}
void writeU32(std::ofstream &out, uint32_t value) {
    const char bytes[]{static_cast<char>(value), static_cast<char>(value >> 8),
        static_cast<char>(value >> 16), static_cast<char>(value >> 24)};
    out.write(bytes, 4);
}
void demo(const std::string &path) {
    auto e = engine();
    sd_set_parameter(e.get(), SD_OSC_TABLE, 1);
    sd_set_parameter(e.get(), SD_OSC_POSITION, .65f);
    sd_set_parameter(e.get(), SD_OSC_UNISON, 3);
    sd_set_parameter(e.get(), SD_OSC_DETUNE, .25f);
    sd_set_parameter(e.get(), SD_CUTOFF, 2200);
    sd_set_parameter(e.get(), SD_RESONANCE, .4f);
    sd_set_parameter(e.get(), SD_DRIVE, .25f);
    sd_set_parameter(e.get(), SD_DELAY, .32f);
    sd_set_parameter(e.get(), SD_SUB_LEVEL, .15f);
    sd_set_parameter(e.get(), SD_LFO_RATE, 3);
    sd_set_modulation(e.get(), 0, SD_SOURCE_LFO1, SD_CUTOFF, .18f);
    Audio song;
    for (int note : {36, 43, 38, 41, 36, 48, 46, 43}) {
        sd_note_on(e.get(), note, .8f);
        auto a = render(e.get(), kRate * 3 / 8);
        song.left.insert(song.left.end(), a.left.begin(), a.left.end());
        song.right.insert(song.right.end(), a.right.begin(), a.right.end());
        sd_note_off(e.get(), note);
        a = render(e.get(), kRate / 8);
        song.left.insert(song.left.end(), a.left.begin(), a.left.end());
        song.right.insert(song.right.end(), a.right.begin(), a.right.end());
    }
    auto tail = render(e.get(), kRate);
    song.left.insert(song.left.end(), tail.left.begin(), tail.left.end());
    song.right.insert(song.right.end(), tail.right.begin(), tail.right.end());
    std::ofstream out(path, std::ios::binary);
    require(out.good(), "cannot open demo WAV");
    const auto bytes = static_cast<uint32_t>(song.left.size() * 4);
    out.write("RIFF", 4); writeU32(out, bytes + 36); out.write("WAVEfmt ", 8);
    writeU32(out, 16); writeU16(out, 1); writeU16(out, 2);
    writeU32(out, kRate); writeU32(out, kRate * 4); writeU16(out, 4); writeU16(out, 16);
    out.write("data", 4); writeU32(out, bytes);
    for (size_t i = 0; i < song.left.size(); ++i) {
        writeU16(out, static_cast<uint16_t>(static_cast<int16_t>(std::clamp(song.left[i], -1.0f, 1.0f) * 32767)));
        writeU16(out, static_cast<uint16_t>(static_cast<int16_t>(std::clamp(song.right[i], -1.0f, 1.0f) * 32767)));
    }
    require(out.good(), "demo WAV write failed");
    std::cout << "Demo WAV: " << path << '\n';
}
}

int main(int argc, char **argv) {
    int passed = 0, failed = 0;
    auto test = [&](const char *name, const std::function<void()> &body) {
        try { body(); ++passed; std::cout << "PASS " << name << '\n'; }
        catch (const std::exception &error) { ++failed; std::cerr << "FAIL " << name << ": " << error.what() << '\n'; }
    };
    test("silence and invalid API inputs", [] {
        auto e = engine();
        require(rms(render(e.get(), 2048).left) == 0, "idle engine is not silent");
        std::array<float, 32> l{}, r{}; l.fill(1); r.fill(1);
        sd_render(nullptr, l.data(), r.data(), 32);
        require(l[0] == 0 && r[31] == 0, "null engine should silence outputs");
        sd_set_parameter(e.get(), -1, 1); sd_set_parameter(e.get(), 159, 1);
        sd_note_on(e.get(), -1, 1); sd_note_on(e.get(), 128, 1);
        require(rms(render(e.get(), 2048).left) == 0, "invalid notes were accepted");
        require(sd_create(0) == nullptr && sd_create(std::numeric_limits<double>::quiet_NaN()) == nullptr,
                "invalid sample rates were accepted");
    });
    test("A4 pitch and semitone transposition", [] {
        auto e = engine(); sd_note_on(e.get(), 69, 1);
        auto a = render(e.get(), kRate);
        require(rms(a.left, 4000) > .05, "held note is silent");
        require(std::abs(pitch(a.left) - 440) < 1, "A4 is out of tune");
        sd_set_parameter(e.get(), SD_OSC_SEMITONES, 12);
        a = render(e.get(), kRate);
        require(std::abs(pitch(a.left) - 880) < 2, "octave transpose failed");
        require(finiteBounded(a), "pitch render contains invalid samples");
    });
    test("ADSR release reaches silence", [] {
        auto e = engine(); sd_set_parameter(e.get(), SD_RELEASE, .08f);
        sd_note_on(e.get(), 60, 1); render(e.get(), kRate / 4);
        sd_note_off(e.get(), 60);
        auto tail = render(e.get(), kRate / 3);
        require(rms(tail.left) > .001, "release has no tail");
        require(rms(tail.left, kRate / 5) < .000001, "note remained active after release");
        sd_note_on(e.get(), 64, 1); sd_note_on(e.get(), 67, 1); render(e.get(), 4096);
        sd_all_notes_off(e.get());
        require(rms(render(e.get(), kRate / 3).left, kRate / 5) < .000001, "all-notes-off left voices active");
    });
    test("four oscillator modes generate different sound", [] {
        std::array<Audio, 4> modes;
        for (int i = 0; i < 4; ++i) {
            modes[i] = held(i);
            require(finiteBounded(modes[i]), "mode has nonfinite or unbounded output");
            require(rms(modes[i].left) > .0001, "mode is silent");
        }
        for (int i = 0; i < 4; ++i) for (int j = i + 1; j < 4; ++j)
            require(difference(modes[i].left, modes[j].left) > .002, "oscillator modes are identical");
    });
    test("pan, level, velocity and master affect sound", [] {
        auto e = engine(); sd_set_parameter(e.get(), SD_OSC_PAN, 1);
        sd_note_on(e.get(), 60, .7f); auto a = render(e.get(), 12000);
        require(rms(a.left) == 0 && rms(a.right) > .01, "hard-right pan failed");
        sd_set_parameter(e.get(), SD_MASTER, 0);
        require(rms(render(e.get(), 2048).right) == 0, "master mute failed");
        auto a1 = engine(), a2 = engine();
        sd_note_on(a1.get(), 60, 1); sd_note_on(a2.get(), 60, .2f);
        require(rms(render(a1.get(), 12000).left) > rms(render(a2.get(), 12000).left) * 2,
                "velocity did not change amplitude");
        sd_set_parameter(a1.get(), SD_OSC_LEVEL, 0);
        require(rms(render(a1.get(), 2048).left, 1000) < .000001, "oscillator mute failed");
    });
    test("wavetable position and table selection affect sound", [] {
        auto a = held(SD_MODE_WAVETABLE, 0, 0), b = held(SD_MODE_WAVETABLE, 1, 0);
        require(difference(a.left, b.left) > .01, "wavetable frame selection failed");
        auto e = engine(); sd_set_parameter(e.get(), SD_OSC_TABLE, 2); sd_set_parameter(e.get(), SD_OSC_POSITION, .5f);
        sd_note_on(e.get(), 60, .85f);
        require(difference(a.left, render(e.get(), kRate / 2).left) > .01, "wavetable bank selection failed");
    });
    test("all three oscillators, unison, fine tuning and warp", [] {
        for (int o = 0; o < 3; ++o) {
            auto e = engine(); sd_set_parameter(e.get(), SD_OSC_LEVEL, 0);
            sd_set_parameter(e.get(), o * 32 + SD_OSC_LEVEL, .7f);
            sd_set_parameter(e.get(), o * 32 + SD_OSC_FINE, 100);
            sd_note_on(e.get(), 69, 1); auto a = render(e.get(), kRate);
            require(std::abs(pitch(a.left) - 440 * std::pow(2.0, 1 / 12.0)) < 2,
                    "oscillator or fine tuning failed");
        }
        auto mono = engine(), wide = engine(); sd_note_on(mono.get(), 60, 1); sd_note_on(wide.get(), 60, 1);
        sd_set_parameter(wide.get(), SD_OSC_UNISON, 4); sd_set_parameter(wide.get(), SD_OSC_DETUNE, .8f);
        auto a = render(mono.get(), 12000), b = render(wide.get(), 12000);
        require(difference(a.left, b.left) > .02, "unison and detune did not change sound");
        require(difference(b.left, b.right) > .01, "unison did not produce stereo spread");
        require(difference(held(SD_MODE_WAVETABLE, .5f, 0).left,
                           held(SD_MODE_WAVETABLE, .5f, .9f).left) > .01, "wavetable phase warp failed");
        require(difference(held(SD_MODE_SPECTRAL, .5f, 0).left,
                           held(SD_MODE_SPECTRAL, .5f, .9f).left) > .01, "spectral partial warp failed");
    });
    test("granular size, density and scan affect playback", [] {
        auto a = engine(), b = engine();
        for (auto *e : {a.get(), b.get()}) {
            sd_set_parameter(e, SD_OSC_MODE, SD_MODE_GRANULAR); sd_note_on(e, 60, 1);
        }
        sd_set_parameter(a.get(), SD_OSC_GRAIN_SIZE, .02f); sd_set_parameter(a.get(), SD_OSC_DENSITY, 8);
        sd_set_parameter(b.get(), SD_OSC_GRAIN_SIZE, .2f); sd_set_parameter(b.get(), SD_OSC_DENSITY, 50);
        require(difference(render(a.get(), kRate).left, render(b.get(), kRate).left) > .005,
                "granular size and density did not change playback");
        auto fixed = engine(), scan = engine();
        for (auto *e : {fixed.get(), scan.get()}) {
            sd_set_parameter(e, SD_OSC_MODE, SD_MODE_GRANULAR); sd_note_on(e, 60, 1);
        }
        sd_set_parameter(scan.get(), SD_OSC_SCAN, 1);
        require(difference(render(fixed.get(), kRate).left, render(scan.get(), kRate).left) > .005,
                "granular scan did not move through sample");
    });
    test("sample import copies data and plays one-shot", [] {
        auto e = engine(); std::vector<float> mono(6000);
        for (size_t i = 0; i < mono.size(); ++i) mono[i] = .7f * std::sin(2 * kPi * 261.625565 * i / kRate);
        require(sd_load_sample(e.get(), 0, mono.data(), static_cast<int>(mono.size()), kRate) == 1,
                "valid sample import failed");
        std::fill(mono.begin(), mono.end(), 0);
        sd_set_parameter(e.get(), SD_OSC_MODE, SD_MODE_SAMPLE); sd_note_on(e.get(), 60, 1);
        auto a = render(e.get(), kRate / 2);
        require(rms(a.left) > .01, "sample was not copied or played");
        require(rms(a.left, 12000) < .000001, "one-shot loops unexpectedly");
        require(sd_load_sample(e.get(), 3, mono.data(), 6000, kRate) == 0, "invalid oscillator import accepted");
        require(sd_load_sample(e.get(), 0, mono.data(), 6000, 100) == 0, "invalid source rate accepted");
        require(sd_load_sample(e.get(), 0, mono.data(), 1000000, kRate) == 0, "overlong sample accepted");
        sd_all_notes_off(e.get()); render(e.get(), kRate);
        sd_set_parameter(e.get(), SD_OSC_MODE, SD_MODE_SPECTRAL); sd_note_on(e.get(), 60, 1);
        require(rms(render(e.get(), 12000).left) > .01, "imported sample spectral resynthesis is silent");
    });
    test("wavetable import, frame interpolation and validation", [] {
        auto e = engine(); std::vector<float> table(256);
        for (int i = 0; i < 128; ++i) {
            table[i] = .7f * std::sin(2 * kPi * i / 128);
            table[128 + i] = .7f * std::sin(2 * kPi * i * 3 / 128);
        }
        require(sd_load_wavetable(e.get(), 0, table.data(), 256, 128) == 1, "valid wavetable rejected");
        std::fill(table.begin(), table.end(), 0);
        sd_note_on(e.get(), 69, 1); auto a = render(e.get(), kRate);
        require(std::abs(pitch(a.left) - 440) < 1, "imported fundamental pitch failed");
        sd_set_parameter(e.get(), SD_OSC_POSITION, 1); auto b = render(e.get(), kRate);
        require(std::abs(pitch(b.left) - 1320) < 2, "imported frame morph failed");
        require(difference(a.left, b.left) > .02, "imported frames sound identical");
        require(sd_load_wavetable(e.get(), 0, table.data(), 255, 128) == 0, "partial frame accepted");
        require(sd_load_wavetable(e.get(), 0, table.data(), 256, 127) == 0, "non-power-two frame accepted");
        require(sd_load_wavetable(e.get(), 0, table.data(), 256, 16) == 0, "too-short frame accepted");
        require(sd_load_wavetable(e.get(), 0, nullptr, 0, 0) == 1, "builtin restore failed");
    });
    test("modulation supports macro, envelope and bipolar LFO", [] {
        auto plain = engine(), modulated = engine();
        for (auto *e : {plain.get(), modulated.get()}) {
            sd_set_parameter(e, SD_OSC_LEVEL, 0); sd_set_parameter(e, SD_MACRO1, .7f); sd_note_on(e, 60, 1);
        }
        sd_set_modulation(modulated.get(), 0, SD_SOURCE_MACRO1, SD_OSC_LEVEL, 1);
        require(rms(render(plain.get(), 12000).left) == 0, "unmodulated muted oscillator is audible");
        require(rms(render(modulated.get(), 12000).left) > .03, "macro route failed");
        sd_set_modulation(modulated.get(), 0, SD_SOURCE_DISABLED, SD_OSC_LEVEL, 1);
        require(rms(render(modulated.get(), 2048).left, 1000) < .000001, "disabled route still active");
        auto e = engine(); sd_set_parameter(e.get(), SD_OSC_LEVEL, 0);
        sd_set_modulation(e.get(), 0, SD_SOURCE_ENV1, SD_OSC_LEVEL, .8f); sd_note_on(e.get(), 60, 1);
        require(rms(render(e.get(), 12000).left) > .03, "envelope route failed");
        auto a = engine(), b = engine(); sd_note_on(a.get(), 69, 1); sd_note_on(b.get(), 69, 1);
        sd_set_modulation(b.get(), 0, SD_SOURCE_LFO1, SD_OSC_SEMITONES, .2f);
        require(difference(render(a.get(), kRate).left, render(b.get(), kRate).left) > .03, "bipolar LFO pitch route failed");
        auto chained = engine(); sd_set_parameter(chained.get(), SD_OSC_LEVEL, 0);
        sd_set_modulation(chained.get(), 0, SD_SOURCE_LFO1, SD_MACRO1, 1);
        sd_set_modulation(chained.get(), 1, SD_SOURCE_MACRO1, SD_OSC_LEVEL, .7f);
        sd_note_on(chained.get(), 60, 1);
        require(rms(render(chained.get(), 12000).left) > .02, "LFO-to-macro-to-parameter chain failed");
    });
    test("filter drive delay and auxiliary oscillators affect output", [] {
        auto low = engine(), high = engine();
        for (auto *e : {low.get(), high.get()}) {
            sd_set_parameter(e, SD_OSC_TABLE, 1); sd_set_parameter(e, SD_OSC_POSITION, .8f); sd_note_on(e, 60, 1);
        }
        sd_set_parameter(low.get(), SD_CUTOFF, 100);
        require(rms(render(high.get(), 12000).left) > rms(render(low.get(), 12000).left) * 3,
                "lowpass cutoff did not attenuate harmonics");
        auto clean = engine(), driven = engine(); sd_note_on(clean.get(), 60, 1); sd_note_on(driven.get(), 60, 1);
        sd_set_parameter(driven.get(), SD_DRIVE, .8f);
        require(difference(render(clean.get(), 12000).left, render(driven.get(), 12000).left) > .01,
                "drive did not change timbre");
        auto e = engine(); sd_set_parameter(e.get(), SD_DELAY, .8f); sd_set_parameter(e.get(), SD_RELEASE, .01f);
        sd_note_on(e.get(), 60, 1); render(e.get(), 3000); sd_note_off(e.get(), 60);
        auto tail = render(e.get(), kRate);
        require(rms(tail.left, kRate / 4) > .001, "delay produced no audible echo");
        sd_set_parameter(e.get(), SD_MASTER, 0);
        require(rms(render(e.get(), 4096).left) == 0, "master did not mute delay tail");
        auto auxiliary = engine(); sd_set_parameter(auxiliary.get(), SD_OSC_LEVEL, 0);
        sd_set_parameter(auxiliary.get(), SD_SUB_LEVEL, .5f); sd_note_on(auxiliary.get(), 69, 1);
        require(std::abs(pitch(render(auxiliary.get(), kRate).left) - 220) < 1, "sub oscillator is not an octave down");
        sd_set_parameter(auxiliary.get(), SD_SUB_LEVEL, 0); sd_set_parameter(auxiliary.get(), SD_NOISE_LEVEL, .7f);
        require(rms(render(auxiliary.get(), 12000).left) > .01, "noise oscillator is silent");
    });
    test("imported wavetables suppress out-of-band harmonics", [] {
        auto e = engine(); std::vector<float> table(2048);
        for (size_t i = 0; i < table.size(); ++i) table[i] = .6f * std::sin(2 * kPi * i * 20 / table.size());
        require(sd_load_wavetable(e.get(), 0, table.data(), static_cast<int>(table.size()), 2048) == 1,
                "high harmonic table import failed");
        sd_note_on(e.get(), 60, 1);
        require(rms(render(e.get(), 12000).left) > .01, "in-band imported harmonic was removed");
        sd_all_notes_off(e.get()); render(e.get(), kRate);
        sd_note_on(e.get(), 100, 1);
        require(rms(render(e.get(), 12000).left) < .00001, "out-of-band imported harmonic aliases");
    });
    test("polyphony overload and extreme controls remain finite", [] {
        auto e = engine();
        for (int o = 0; o < 3; ++o) {
            sd_set_parameter(e.get(), o * 32 + SD_OSC_MODE, static_cast<float>(o));
            sd_set_parameter(e.get(), o * 32 + SD_OSC_UNISON, 4);
            sd_set_parameter(e.get(), o * 32 + SD_OSC_LEVEL, 1);
            sd_set_parameter(e.get(), o * 32 + SD_OSC_DETUNE, 1);
            sd_set_parameter(e.get(), o * 32 + SD_OSC_WARP, 1);
        }
        sd_set_parameter(e.get(), SD_RESONANCE, 1); sd_set_parameter(e.get(), SD_DRIVE, 1);
        sd_set_parameter(e.get(), SD_DELAY, 1); sd_set_parameter(e.get(), SD_MASTER, 1);
        sd_set_parameter(e.get(), SD_CUTOFF, std::numeric_limits<float>::infinity());
        for (int note = 36; note < 60; ++note) sd_note_on(e.get(), note, 1);
        require(finiteBounded(render(e.get(), kRate)), "voice stealing or extreme parameters corrupted audio");
        sd_all_notes_off(e.get()); require(finiteBounded(render(e.get(), kRate)), "effect tail corrupted audio");
    });
    test("queue overflow cannot leave a stuck note", [] {
        auto e = engine(); sd_note_on(e.get(), 60, 1); render(e.get(), 1024);
        for (int i = 0; i < 1000; ++i) sd_note_on(e.get(), 60 + i % 12, 1);
        for (int i = 0; i < 1000; ++i) sd_note_off(e.get(), 60 + i % 12);
        require(rms(render(e.get(), kRate).left, kRate / 2) == 0, "overflow left unmatched notes active");
        sd_note_on(e.get(), 72, 1);
        require(rms(render(e.get(), 4096).left) > .01, "queue failed to recover after overflow");
    });
    test("concurrent control writes and rendering", [] {
        auto e = engine(); std::atomic<bool> done{false};
        std::thread producer([&] {
            for (int i = 0; i < 3000; ++i) {
                sd_set_parameter(e.get(), SD_CUTOFF, 100 + i % 19000);
                sd_set_parameter(e.get(), SD_MACRO1, (i % 100) / 100.0f);
                sd_set_modulation(e.get(), i % 16, SD_SOURCE_MACRO1, SD_OSC_POSITION, .4f);
                sd_note_on(e.get(), 48 + i % 24, .7f); sd_note_off(e.get(), 48 + i % 24);
            }
            done.store(true, std::memory_order_release);
        });
        bool valid = true;
        do { valid = valid && finiteBounded(render(e.get(), 1024)); }
        while (!done.load(std::memory_order_acquire));
        producer.join();
        require(valid, "concurrent controls corrupted output");
        sd_all_notes_off(e.get());
        require(rms(render(e.get(), kRate).left, kRate / 2) < .000001, "concurrent commands left stuck notes");
    });
    std::cout << passed << " scenarios, " << assertions << " assertions, " << failed << " failures\n";
    if (failed == 0 && argc == 3 && std::string(argv[1]) == "--demo") {
        try { demo(argv[2]); } catch (const std::exception &error) { std::cerr << error.what() << '\n'; return 1; }
    }
    return failed == 0 ? 0 : 1;
}
