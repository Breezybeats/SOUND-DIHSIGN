#include "SoundCore.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <complex>
#include <cstdint>
#include <cstring>
#include <limits>
#include <new>
#include <vector>

namespace {
constexpr int kOscillators = 3, kVoices = 8, kParameters = 160;
constexpr int kTableSize = 2048, kFrames = 4, kHarmonics = 24;
constexpr int kQueueSize = 256, kModSlots = 16, kGrains = 16;
constexpr int kMipLevels = 5;
constexpr std::array<int, kMipLevels> kMipHarmonics{{24, 12, 6, 3, 1}};
constexpr double kPi = 3.14159265358979323846;

float bounded(float value, float low, float high) {
    return std::isfinite(value) ? std::clamp(value, low, high) : low;
}
double wrap(double x) { return x - std::floor(x); }
float sine(double phase) { return static_cast<float>(std::sin(2.0 * kPi * phase)); }

struct Range { float low, high; bool logarithmic; };
bool validParameter(int id) {
    return (id >= 0 && id < 96 && id % 32 <= SD_OSC_OCTAVE) ||
           (id >= SD_CUTOFF && id <= SD_MACRO1);
}
bool continuousParameter(int id) {
    return validParameter(id) && !(id < 96 && (id % 32 == SD_OSC_MODE ||
        id % 32 == SD_OSC_TABLE || id % 32 == SD_OSC_UNISON || id % 32 == SD_OSC_OCTAVE));
}
Range parameterRange(int id) {
    if (id < 96) {
        switch (id % 32) {
            case SD_OSC_MODE: return {0, 3, false};
            case SD_OSC_TABLE: return {0, 2, false};
            case SD_OSC_SEMITONES: return {-24, 24, false};
            case SD_OSC_OCTAVE: return {-4, 4, false};
            case SD_OSC_FINE: return {-100, 100, false};
            case SD_OSC_UNISON: return {1, 4, false};
            case SD_OSC_GRAIN_SIZE: return {.01f, .25f, true};
            case SD_OSC_DENSITY: return {1, 60, true};
            default: return {0, 1, false};
        }
    }
    switch (id) {
        case SD_CUTOFF: return {20, 20000, true};
        case SD_LFO_RATE: return {.05f, 20, true};
        case SD_ATTACK: case SD_DECAY: case SD_RELEASE: return {.001f, 5, true};
        default: return {0, 1, false};
    }
}
float normalize(int id, float v) {
    const auto r = parameterRange(id);
    return r.logarithmic ? std::log(v / r.low) / std::log(r.high / r.low)
                         : (v - r.low) / (r.high - r.low);
}
float denormalize(int id, float v) {
    const auto r = parameterRange(id);
    return r.logarithmic ? r.low * std::pow(r.high / r.low, v)
                         : r.low + v * (r.high - r.low);
}
float parameter(const std::array<float, kParameters> &base,
                const std::array<float, kParameters> &offset, int id) {
    return offset[id] == 0 ? base[id] : denormalize(id,
        std::clamp(normalize(id, base[id]) + offset[id], 0.0f, 1.0f));
}
uint32_t randomBits(uint32_t &state) {
    state ^= state << 13; state ^= state >> 17; state ^= state << 5;
    return state;
}
float randomUnit(uint32_t &state) {
    return static_cast<float>(randomBits(state) >> 8) / 16777216.0f;
}

struct SampleData {
    std::vector<float> data;
    double rate = 24000;
    std::array<float, kHarmonics> harmonics{};
    bool imported = false;
};
struct WavetableData {
    int frameSize = 0, frameCount = 0;
    std::vector<std::vector<float>> levels;
    std::vector<int> harmonicLimits;
    std::vector<std::array<float, kHarmonics>> harmonics;
};
void fft(std::vector<std::complex<double>> &values, bool inverse) {
    const size_t n = values.size();
    for (size_t i = 1, j = 0; i < n; ++i) {
        size_t bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) std::swap(values[i], values[j]);
    }
    for (size_t length = 2; length <= n; length <<= 1) {
        const double angle = (inverse ? 2 : -2) * kPi / length;
        const std::complex<double> step(std::cos(angle), std::sin(angle));
        for (size_t start = 0; start < n; start += length) {
            std::complex<double> weight(1, 0);
            for (size_t j = 0; j < length / 2; ++j) {
                const auto a = values[start + j];
                const auto b = values[start + j + length / 2] * weight;
                values[start + j] = a + b; values[start + j + length / 2] = a - b;
                weight *= step;
            }
        }
    }
    if (inverse) for (auto &v : values) v /= static_cast<double>(n);
}
struct Grain {
    double cursor = 0, increment = 1;
    float phase = 1, step = 1, pan = .5f;
    bool active = false;
};
struct OscillatorState {
    std::array<double, 4> phase{}, cursor{};
    std::array<std::array<double, kHarmonics>, 4> partialPhase{};
    std::array<Grain, kGrains> grains{};
    double scan = 0, spawnClock = 0;
    int nextGrain = 0;
};
enum class EnvelopeStage { off, attack, decay, sustain, release };
struct FilterState { float ic1 = 0, ic2 = 0; };
struct Voice {
    bool active = false;
    int note = 60;
    uint64_t age = 0;
    float velocity = 1, envelope = 0, releaseLevel = 0;
    EnvelopeStage stage = EnvelopeStage::off;
    std::array<OscillatorState, kOscillators> oscillators{};
    std::array<FilterState, 2> filter{};
    double subPhase = 0;
    uint32_t random = 0x9e3779b9;
};
struct Command { int type = 0, note = 0; float velocity = 0; };
struct Modulation { int source = 0, destination = 0; float amount = 0; };

float sampleAt(const SampleData &sample, double cursor, bool loop) {
    const int count = static_cast<int>(sample.data.size());
    if (count < 2 || (!loop && (cursor < 0 || cursor >= count - 1))) return 0;
    if (loop) cursor = wrap(cursor / count) * count;
    const int index = static_cast<int>(cursor);
    const float fraction = static_cast<float>(cursor - index);
    return sample.data[index] + (sample.data[(index + 1) % count] -
        sample.data[index]) * fraction;
}
float lowpass(FilterState &state, float input, float g, float resonance) {
    const float k = 2.0f - 1.9f * resonance;
    const float a1 = 1.0f / (1.0f + g * (g + k));
    const float a2 = g * a1, a3 = g * a2;
    const float v3 = input - state.ic2;
    const float v1 = a1 * state.ic1 + a2 * v3;
    const float v2 = state.ic2 + a2 * state.ic1 + a3 * v3;
    state.ic1 = 2 * v1 - state.ic1;
    state.ic2 = 2 * v2 - state.ic2;
    return v2;
}
}

struct SD_Engine {
    double rate;
    std::array<std::atomic<float>, kParameters> parameters;
    std::array<std::atomic<uint64_t>, kModSlots> modulation;
    std::array<Command, kQueueSize> commands{};
    std::atomic<unsigned> readIndex{0}, writeIndex{0};
    std::atomic<bool> emergencyReset{false};
    std::array<Voice, kVoices> voices{};
    std::array<SampleData, kOscillators> samples;
    std::array<WavetableData, kOscillators> importedTables;
    std::array<std::array<std::array<std::array<float, kTableSize + 1>, kMipLevels>, kFrames>, 3> tables{};
    std::array<std::array<std::array<float, kHarmonics>, kFrames>, 3> spectra{};
    std::array<float, kTableSize + 1> sineTable{};
    std::vector<float> delayLeft, delayRight;
    size_t delayIndex = 0;
    double lfoPhase = 0;
    uint64_t age = 0;

    explicit SD_Engine(double sampleRate) : rate(sampleRate),
        delayLeft(static_cast<size_t>(sampleRate * 2) + 1),
        delayRight(static_cast<size_t>(sampleRate * 2) + 1) {
        for (auto &p : parameters) p.store(0, std::memory_order_relaxed);
        for (auto &m : modulation) m.store(0, std::memory_order_relaxed);
        for (int o = 0; o < kOscillators; ++o) {
            const int b = o * 32;
            parameters[b + SD_OSC_LEVEL] = o == 0 ? .7f : 0;
            parameters[b + SD_OSC_UNISON] = 1;
            parameters[b + SD_OSC_PAN] = .5f;
            parameters[b + SD_OSC_GRAIN_SIZE] = .09f;
            parameters[b + SD_OSC_DENSITY] = 24;
        }
        parameters[SD_CUTOFF] = 16000;
        parameters[SD_RESONANCE] = .15f;
        parameters[SD_LFO_RATE] = 1;
        parameters[SD_MASTER] = .7f;
        parameters[SD_ATTACK] = .008f;
        parameters[SD_DECAY] = .15f;
        parameters[SD_SUSTAIN] = .8f;
        parameters[SD_RELEASE] = .25f;
        for (int i = 0; i <= kTableSize; ++i)
            sineTable[i] = sine(static_cast<double>(i) / kTableSize);
        makeTables();
        makeSamples();
    }

    float fastSine(double phase) const {
        const double position = wrap(phase) * kTableSize;
        const int i = static_cast<int>(position);
        return sineTable[i] + static_cast<float>(position - i) *
            (sineTable[i + 1] - sineTable[i]);
    }
    void makeTables() {
        for (int table = 0; table < 3; ++table) {
            for (int frame = 0; frame < kFrames; ++frame) {
                auto &spectrum = spectra[table][frame];
                for (int h = 1; h <= kHarmonics; ++h) {
                    float amplitude = 0;
                    if (table == 0) {
                        if (frame == 0) amplitude = h == 1 ? 1 : 0;
                        if (frame == 1) amplitude = 1.0f / h;
                        if (frame == 2) amplitude = h % 2 ? 1.0f / h : 0;
                        if (frame == 3) amplitude = h % 2 ?
                            ((h % 4 == 1 ? 1.0f : -1.0f) / (h * h)) : 0;
                    } else if (table == 1) {
                        const float center = 3.0f + frame * 3.5f;
                        amplitude = (h == 1 ? .65f : 0) +
                            std::exp(-.08f * (h - center) * (h - center)) /
                            std::sqrt(static_cast<float>(h));
                        if (h % 3 == 0) amplitude *= .25f;
                    } else {
                        const float center = 5.0f + frame * 4.0f;
                        amplitude = h % 2 ? .8f / h +
                            .6f * std::exp(-.16f * (h - center) * (h - center)) : .04f / h;
                    }
                    spectrum[h - 1] = amplitude;
                }
                float maximum = 0;
                auto &wave = tables[table][frame][0];
                for (int i = 0; i < kTableSize; ++i) {
                    float value = 0;
                    for (int h = 1; h <= kHarmonics; ++h)
                        value += spectrum[h - 1] * fastSine(static_cast<double>(i) * h / kTableSize);
                    wave[i] = value;
                    maximum = std::max(maximum, std::abs(value));
                }
                for (auto &h : spectrum) h /= std::max(.001f, maximum);
                for (int i = 0; i < kTableSize; ++i) wave[i] /= std::max(.001f, maximum);
                wave[kTableSize] = wave[0];
                for (int level = 1; level < kMipLevels; ++level) {
                    auto &filtered = tables[table][frame][level];
                    for (int i = 0; i < kTableSize; ++i) {
                        float value = 0;
                        for (int h = 1; h <= kMipHarmonics[level]; ++h)
                            value += spectrum[h - 1] * fastSine(static_cast<double>(i) * h / kTableSize);
                        filtered[i] = value;
                    }
                    filtered[kTableSize] = filtered[0];
                }
            }
        }
    }
    void makeSamples() {
        for (int o = 0; o < kOscillators; ++o) {
            auto &sample = samples[o];
            sample.data.resize(30000);
            for (size_t i = 0; i < sample.data.size(); ++i) {
                const double time = i / sample.rate;
                const double p = 261.625565 * time;
                const float attack = std::min(1.0f, static_cast<float>(time * 200));
                sample.data[i] = attack * std::exp(static_cast<float>(-3.0 * time)) *
                    (.62f * fastSine(p) + .23f * fastSine(p * 2.01) +
                     .13f * fastSine(p * 4.0 + .3 * std::sin(time * 12)));
            }
        }
    }
    float wavetable(int oscillator, int table, float position, double phase, double frequency) const {
        const auto &imported = importedTables[oscillator];
        const int allowed = std::max(1, static_cast<int>(rate * .45 / frequency));
        if (imported.frameCount > 0) {
            size_t level = 0;
            while (level + 1 < imported.levels.size() && imported.harmonicLimits[level] > allowed) ++level;
            const auto &data = imported.levels[level];
            const float frame = position * (imported.frameCount - 1);
            const int a = static_cast<int>(frame), b = std::min(a + 1, imported.frameCount - 1);
            const double index = wrap(phase) * imported.frameSize;
            const int i = static_cast<int>(index), j = (i + 1) % imported.frameSize;
            const float frac = static_cast<float>(index - i);
            const float x = data[a * imported.frameSize + i] * (1 - frac) + data[a * imported.frameSize + j] * frac;
            const float y = data[b * imported.frameSize + i] * (1 - frac) + data[b * imported.frameSize + j] * frac;
            return x + (frame - a) * (y - x);
        }
        int level = 0;
        while (level + 1 < kMipLevels && kMipHarmonics[level] > allowed) ++level;
        const float f = position * (kFrames - 1);
        const int a = std::min(kFrames - 2, static_cast<int>(f));
        const float mix = f - a;
        const double index = wrap(phase) * kTableSize;
        const int i = static_cast<int>(index);
        const float frac = static_cast<float>(index - i);
        const auto &x = tables[table][a][level], &y = tables[table][a + 1][level];
        const float first = x[i] + frac * (x[i + 1] - x[i]);
        const float second = y[i] + frac * (y[i + 1] - y[i]);
        return first + mix * (second - first);
    }
    float spectral(int oscillator, int table, float position, std::array<double, kHarmonics> &phases,
                   double frequency, float warpAmount) const {
        const float f = position * (kFrames - 1);
        const int a = std::min(kFrames - 2, static_cast<int>(f));
        const float mix = f - a;
        float value = 0;
        const auto &sample = samples[oscillator];
        const auto &imported = importedTables[oscillator];
        for (int h = 1; h <= kHarmonics; ++h) {
            const double partial = h + warpAmount * .015 * h * h;
            if (partial * frequency >= rate * .45) break;
            float amplitude = sample.imported ? sample.harmonics[h - 1] :
                spectra[table][a][h - 1] * (1 - mix) + spectra[table][a + 1][h - 1] * mix;
            if (imported.frameCount > 0) {
                const float frame = position * (imported.frameCount - 1);
                const int first = static_cast<int>(frame), second = std::min(first + 1, imported.frameCount - 1);
                amplitude = imported.harmonics[first][h - 1] * (1 - (frame - first)) +
                    imported.harmonics[second][h - 1] * (frame - first);
            }
            const float tilt = 1.0f / (1.0f + position * h * .13f);
            // Warp separates partials; this is deliberately distinct from table playback.
            value += amplitude * tilt * fastSine(phases[h - 1]);
            phases[h - 1] = wrap(phases[h - 1] + frequency * partial / rate);
        }
        return value;
    }
    void enqueue(Command command) {
        const auto write = writeIndex.load(std::memory_order_relaxed);
        const auto next = (write + 1) % kQueueSize;
        if (next == readIndex.load(std::memory_order_acquire)) {
            emergencyReset.store(true, std::memory_order_release);
            return;
        }
        commands[write] = command;
        writeIndex.store(next, std::memory_order_release);
    }
    void beginNote(int note, float velocity) {
        Voice *voice = nullptr;
        for (auto &candidate : voices) if (!candidate.active) { voice = &candidate; break; }
        if (!voice) voice = &*std::min_element(voices.begin(), voices.end(),
            [](const Voice &a, const Voice &b) { return a.age < b.age; });
        *voice = Voice{};
        voice->active = true; voice->note = note; voice->velocity = velocity;
        voice->stage = EnvelopeStage::attack; voice->age = ++age;
        voice->random ^= static_cast<uint32_t>(age * 7919 + note * 997);
        for (auto &o : voice->oscillators)
            for (int u = 1; u < 4; ++u) o.phase[u] = randomUnit(voice->random);
    }
    void release(Voice &voice) {
        if (voice.active && voice.stage != EnvelopeStage::release) {
            voice.releaseLevel = voice.envelope;
            voice.stage = EnvelopeStage::release;
        }
    }
    void consumeCommands() {
        if (emergencyReset.exchange(false, std::memory_order_acq_rel)) {
            for (auto &voice : voices) voice = Voice{};
            // Discard commands preceding the reset, including unmatched note-ons.
            readIndex.store(writeIndex.load(std::memory_order_acquire), std::memory_order_release);
        }
        auto read = readIndex.load(std::memory_order_relaxed);
        const auto write = writeIndex.load(std::memory_order_acquire);
        while (read != write) {
            const auto command = commands[read];
            if (command.type == 1) beginNote(command.note, command.velocity);
            else for (auto &voice : voices)
                if (command.type == 3 || voice.note == command.note) release(voice);
            read = (read + 1) % kQueueSize;
        }
        readIndex.store(read, std::memory_order_release);
    }
    void offsets(std::array<float, kParameters> &out,
                 const std::array<Modulation, kModSlots> &mods,
                 float lfo, float envelope, float velocity, float macro) const {
        out.fill(0);
        // Resolve macro destinations once before using the macro as a source.
        // This supports LFO/envelope -> macro -> parameter without an unbounded
        // recursive matrix, and keeps self-routes deterministic and bounded.
        float macroOffset = 0;
        for (const auto &m : mods) {
            if (m.destination != SD_MACRO1) continue;
            switch (m.source) {
                case SD_SOURCE_LFO1: macroOffset += lfo * m.amount; break;
                case SD_SOURCE_ENV1: macroOffset += envelope * m.amount; break;
                case SD_SOURCE_VELOCITY: macroOffset += velocity * m.amount; break;
                case SD_SOURCE_MACRO1: macroOffset += macro * m.amount; break;
                default: break;
            }
        }
        macro = std::clamp(macro + macroOffset, 0.0f, 1.0f);
        for (const auto &m : mods) {
            float source = 0;
            switch (m.source) {
                case SD_SOURCE_LFO1: source = lfo; break;
                case SD_SOURCE_ENV1: source = envelope; break;
                case SD_SOURCE_VELOCITY: source = velocity; break;
                case SD_SOURCE_MACRO1: source = macro; break;
                default: continue;
            }
            out[m.destination] += source * m.amount;
        }
    }
    void envelope(Voice &v, const std::array<float, kParameters> &base,
                  const std::array<float, kParameters> &offset) const {
        const float sustain = parameter(base, offset, SD_SUSTAIN);
        switch (v.stage) {
            case EnvelopeStage::attack:
                v.envelope += static_cast<float>(1 / (rate * parameter(base, offset, SD_ATTACK)));
                if (v.envelope >= 1) { v.envelope = 1; v.stage = EnvelopeStage::decay; }
                break;
            case EnvelopeStage::decay:
                v.envelope -= static_cast<float>((1 - sustain) / (rate * parameter(base, offset, SD_DECAY)));
                if (v.envelope <= sustain) { v.envelope = sustain; v.stage = EnvelopeStage::sustain; }
                break;
            case EnvelopeStage::sustain: v.envelope = sustain; break;
            case EnvelopeStage::release:
                v.envelope -= static_cast<float>(v.releaseLevel / (rate * parameter(base, offset, SD_RELEASE)));
                if (v.envelope <= .000001f) {
                    v.envelope = 0; v.active = false; v.stage = EnvelopeStage::off;
                }
                break;
            case EnvelopeStage::off: v.active = false; break;
        }
    }
    void oscillator(Voice &voice, int o, const std::array<float, kParameters> &base,
                    const std::array<float, kParameters> &offset, float &left, float &right) {
        const int b = o * 32;
        const float level = parameter(base, offset, b + SD_OSC_LEVEL);
        if (level <= 0) return;
        const int mode = static_cast<int>(base[b + SD_OSC_MODE]);
        const int table = static_cast<int>(base[b + SD_OSC_TABLE]);
        const int unison = static_cast<int>(base[b + SD_OSC_UNISON]);
        const float position = parameter(base, offset, b + SD_OSC_POSITION);
        const float pan = parameter(base, offset, b + SD_OSC_PAN);
        const float warpAmount = parameter(base, offset, b + SD_OSC_WARP);
        const float detune = parameter(base, offset, b + SD_OSC_DETUNE);
        const float scan = parameter(base, offset, b + SD_OSC_SCAN);
        const double frequency = 440 * std::pow(2.0,
            (voice.note - 69 + base[b + SD_OSC_OCTAVE] * 12 +
             parameter(base, offset, b + SD_OSC_SEMITONES) +
             parameter(base, offset, b + SD_OSC_FINE) / 100.0) / 12.0);
        auto &state = voice.oscillators[o];
        const auto &sample = samples[o];
        if (mode == SD_MODE_GRANULAR) {
            const float grainSize = parameter(base, offset, b + SD_OSC_GRAIN_SIZE);
            const float density = parameter(base, offset, b + SD_OSC_DENSITY);
            if (state.spawnClock <= 0) {
                auto &grain = state.grains[state.nextGrain];
                state.nextGrain = (state.nextGrain + 1) % kGrains;
                grain.active = true; grain.phase = 0;
                grain.step = static_cast<float>(1 / (grainSize * rate));
                const double locus = wrap(position + state.scan +
                    (randomUnit(voice.random) - .5) * .025 * unison);
                grain.cursor = locus * sample.data.size();
                const float spread = (randomUnit(voice.random) - .5f) * detune * 60;
                grain.increment = sample.rate / rate * frequency / 261.625565 *
                    std::pow(2.0, spread / 1200.0);
                grain.pan = std::clamp(pan + (randomUnit(voice.random) - .5f) *
                    .18f * (unison - 1), 0.0f, 1.0f);
                state.spawnClock += rate / density;
            }
            state.spawnClock -= 1;
            state.scan = wrap(state.scan + scan * .5 / rate);
            const float gain = level / std::sqrt(std::max(1.0f, density * grainSize));
            for (auto &grain : state.grains) {
                if (!grain.active) continue;
                const float window = .5f - .5f * fastSine(grain.phase + .25);
                float value = sampleAt(sample, grain.cursor, true) * window * gain;
                if (warpAmount > 0) value = std::tanh(value * (1 + warpAmount * 8));
                left += value * std::sqrt(1 - grain.pan);
                right += value * std::sqrt(grain.pan);
                grain.cursor += grain.increment; grain.phase += grain.step;
                if (grain.phase >= 1) grain.active = false;
            }
            return;
        }
        for (int u = 0; u < unison; ++u) {
            const float spread = unison == 1 ? 0 : (2.0f * u / (unison - 1) - 1);
            const double tuned = frequency * std::pow(2.0, spread * detune * 50 / 1200.0);
            float value;
            if (mode == SD_MODE_SAMPLE) {
                value = sampleAt(sample, state.cursor[u] + position * sample.data.size(), false);
                state.cursor[u] += sample.rate / rate * tuned / 261.625565;
                if (warpAmount > 0) value = std::tanh(value * (1 + warpAmount * 8));
            } else if (mode == SD_MODE_SPECTRAL) {
                value = spectral(o, table, position, state.partialPhase[u], tuned, warpAmount);
            } else {
                const double warped = state.phase[u] + warpAmount * .14 * fastSine(state.phase[u]);
                value = wavetable(o, table, position, warped, tuned);
            }
            state.phase[u] = wrap(state.phase[u] + tuned / rate);
            const float stereo = std::clamp(pan + spread * .2f, 0.0f, 1.0f);
            const float amplitude = value * level / std::sqrt(static_cast<float>(unison));
            left += amplitude * std::sqrt(1 - stereo);
            right += amplitude * std::sqrt(stereo);
        }
    }
};

extern "C" {
SD_Engine *sd_create(double sample_rate) {
    if (!std::isfinite(sample_rate) || sample_rate < 8000 || sample_rate > 192000) return nullptr;
    // The real-time contract requires lock-free control atomics on this platform.
    if (!std::atomic<float>{}.is_lock_free() || !std::atomic<uint64_t>{}.is_lock_free()) return nullptr;
    try { return new SD_Engine(sample_rate); } catch (...) { return nullptr; }
}
void sd_destroy(SD_Engine *engine) { delete engine; }
void sd_set_parameter(SD_Engine *engine, int id, float value) {
    if (!engine || !validParameter(id)) return;
    const auto range = parameterRange(id);
    value = bounded(value, range.low, range.high);
    if (!continuousParameter(id)) value = std::round(value);
    engine->parameters[id].store(value, std::memory_order_relaxed);
}
void sd_note_on(SD_Engine *engine, int note, float velocity) {
    if (!engine || note < 0 || note > 127) return;
    velocity = bounded(velocity, 0, 1);
    if (velocity == 0) sd_note_off(engine, note);
    else engine->enqueue({1, note, velocity});
}
void sd_note_off(SD_Engine *engine, int note) {
    if (engine && note >= 0 && note <= 127) engine->enqueue({2, note, 0});
}
void sd_all_notes_off(SD_Engine *engine) {
    if (engine) engine->enqueue({3, 0, 0});
}
void sd_set_modulation(SD_Engine *engine, int slot, int source, int destination, float amount) {
    if (!engine || slot < 0 || slot >= kModSlots) return;
    if (source < SD_SOURCE_DISABLED || source > SD_SOURCE_MACRO1 ||
        !continuousParameter(destination)) source = SD_SOURCE_DISABLED;
    amount = bounded(amount, -1, 1);
    uint32_t bits; std::memcpy(&bits, &amount, sizeof(bits));
    const uint64_t packed = static_cast<uint64_t>(bits) << 16 |
        static_cast<uint64_t>(source ? destination : 0) << 8 | static_cast<uint64_t>(source);
    engine->modulation[slot].store(packed, std::memory_order_relaxed);
}
void sd_render(SD_Engine *engine, float *left, float *right, int frames) {
    if (!left || !right || frames <= 0) return;
    if (!engine) { std::fill_n(left, frames, 0); std::fill_n(right, frames, 0); return; }
    engine->consumeCommands();
    std::array<float, kParameters> base{}, offset{}, globalOffset{};
    std::array<Modulation, kModSlots> mods{};
    for (int id = 0; id < kParameters; ++id)
        base[id] = engine->parameters[id].load(std::memory_order_relaxed);
    for (int slot = 0; slot < kModSlots; ++slot) {
        const auto packed = engine->modulation[slot].load(std::memory_order_relaxed);
        const auto bits = static_cast<uint32_t>(packed >> 16);
        mods[slot].source = static_cast<int>(packed & 255);
        mods[slot].destination = static_cast<int>((packed >> 8) & 255);
        std::memcpy(&mods[slot].amount, &bits, sizeof(bits));
    }
    for (int i = 0; i < frames; ++i) {
        float sumLeft = 0, sumRight = 0, peakEnv = 0, peakVelocity = 0;
        const float lfo = engine->fastSine(engine->lfoPhase);
        for (auto &voice : engine->voices) {
            if (!voice.active) continue;
            engine->offsets(offset, mods, lfo, voice.envelope, voice.velocity, base[SD_MACRO1]);
            engine->envelope(voice, base, offset);
            if (!voice.active) continue;
            peakEnv = std::max(peakEnv, voice.envelope);
            peakVelocity = std::max(peakVelocity, voice.velocity);
            float vLeft = 0, vRight = 0;
            for (int o = 0; o < kOscillators; ++o)
                engine->oscillator(voice, o, base, offset, vLeft, vRight);
            const double frequency = 440 * std::pow(2.0, (voice.note - 69) / 12.0);
            const float sub = engine->fastSine(voice.subPhase) * parameter(base, offset, SD_SUB_LEVEL);
            voice.subPhase = wrap(voice.subPhase + frequency * .5 / engine->rate);
            const float noise = (randomUnit(voice.random) * 2 - 1) *
                parameter(base, offset, SD_NOISE_LEVEL) * .35f;
            vLeft += (sub + noise) * .70710678f; vRight += (sub + noise) * .70710678f;
            const float drive = parameter(base, offset, SD_DRIVE);
            if (drive > 0) {
                const float gain = 1 + drive * 12;
                vLeft = std::tanh(vLeft * gain) / std::sqrt(gain);
                vRight = std::tanh(vRight * gain) / std::sqrt(gain);
            }
            const float cutoff = std::min(parameter(base, offset, SD_CUTOFF), static_cast<float>(engine->rate * .45));
            const float g = static_cast<float>(std::tan(kPi * cutoff / engine->rate));
            const float resonance = parameter(base, offset, SD_RESONANCE);
            const float gain = voice.envelope * voice.velocity;
            sumLeft += lowpass(voice.filter[0], vLeft, g, resonance) * gain;
            sumRight += lowpass(voice.filter[1], vRight, g, resonance) * gain;
        }
        engine->offsets(globalOffset, mods, lfo, peakEnv, peakVelocity, base[SD_MACRO1]);
        engine->lfoPhase = wrap(engine->lfoPhase + parameter(base, globalOffset, SD_LFO_RATE) / engine->rate);
        const auto size = engine->delayLeft.size(), index = engine->delayIndex;
        const auto tapLeft = (index + size - static_cast<size_t>(engine->rate * .30)) % size;
        const auto tapRight = (index + size - static_cast<size_t>(engine->rate * .42)) % size;
        const float delayedLeft = engine->delayLeft[tapLeft], delayedRight = engine->delayRight[tapRight];
        const float wet = parameter(base, globalOffset, SD_DELAY);
        engine->delayLeft[index] = sumLeft + delayedRight * wet * .45f;
        engine->delayRight[index] = sumRight + delayedLeft * wet * .45f;
        engine->delayIndex = (index + 1) % size;
        const float master = parameter(base, globalOffset, SD_MASTER);
        const float outLeft = (sumLeft + delayedLeft * wet * .7f) * master;
        const float outRight = (sumRight + delayedRight * wet * .7f) * master;
        left[i] = std::isfinite(outLeft) ? outLeft / (1 + std::abs(outLeft)) : 0;
        right[i] = std::isfinite(outRight) ? outRight / (1 + std::abs(outRight)) : 0;
    }
}

int sd_load_sample(SD_Engine *engine, int oscillator, const float *mono, int frames, double source_rate) {
    if (!engine || oscillator < 0 || oscillator >= kOscillators || !mono ||
        frames < 2 || !std::isfinite(source_rate) || source_rate < 8000 || source_rate > 192000 ||
        frames > source_rate * 10) return 0;
    try {
        SampleData sample;
        sample.rate = source_rate; sample.imported = true;
        sample.data.resize(static_cast<size_t>(frames));
        for (int i = 0; i < frames; ++i) sample.data[i] = bounded(mono[i], -1, 1);
        // Offline 2048-point spectral analysis. Find the strongest low-frequency
        // bin and preserve relative magnitudes of its first 24 harmonics.
        constexpr int size = 2048, bins = 512;
        std::array<double, bins> magnitudes{};
        int fundamental = 1; double maximum = 0;
        for (int bin = 1; bin < bins; ++bin) {
            double real = 0, imaginary = 0;
            for (int i = 0; i < size; ++i) {
                const float value = i < frames ? sample.data[i] : 0;
                const double window = .5 - .5 * std::cos(2 * kPi * i / (size - 1));
                const double angle = 2 * kPi * bin * i / size;
                real += value * window * std::cos(angle);
                imaginary -= value * window * std::sin(angle);
            }
            magnitudes[bin] = std::hypot(real, imaginary);
            if (bin < 80 && magnitudes[bin] > maximum) {
                maximum = magnitudes[bin]; fundamental = bin;
            }
        }
        double total = 0;
        for (int h = 1; h <= kHarmonics; ++h) {
            const int bin = fundamental * h;
            double magnitude = bin < bins ? magnitudes[bin] : 0;
            if (bin > 1 && bin < bins - 1)
                magnitude = std::max({magnitude, magnitudes[bin - 1], magnitudes[bin + 1]});
            sample.harmonics[h - 1] = static_cast<float>(magnitude);
            total += magnitude;
        }
        if (total > 0) for (auto &h : sample.harmonics) h = static_cast<float>(h / total);
        engine->samples[oscillator] = std::move(sample);
        return 1;
    } catch (...) { return 0; }
}
int sd_load_wavetable(SD_Engine *engine, int oscillator, const float *samples,
                      int sample_count, int frame_size) {
    if (!engine || oscillator < 0 || oscillator >= kOscillators) return 0;
    if (!samples && sample_count == 0 && frame_size == 0) {
        engine->importedTables[oscillator] = WavetableData{};
        return 1;
    }
    if (!samples || frame_size < 32 || frame_size > 2048 || (frame_size & (frame_size - 1)) ||
        sample_count < frame_size || sample_count % frame_size || sample_count / frame_size > 256) return 0;
    try {
        WavetableData table;
        table.frameSize = frame_size; table.frameCount = sample_count / frame_size;
        for (int limit = frame_size / 2; limit >= 1; limit /= 2) {
            table.harmonicLimits.push_back(limit);
            table.levels.emplace_back(static_cast<size_t>(sample_count));
        }
        table.harmonics.resize(table.frameCount);
        std::vector<std::complex<double>> spectrum(frame_size), filtered(frame_size);
        for (int frame = 0; frame < table.frameCount; ++frame) {
            for (int i = 0; i < frame_size; ++i) spectrum[i] = bounded(samples[frame * frame_size + i], -1, 1);
            fft(spectrum, false);
            for (int h = 1; h <= kHarmonics; ++h)
                table.harmonics[frame][h - 1] = h < frame_size / 2 ?
                    static_cast<float>(2 * std::abs(spectrum[h]) / frame_size) : 0;
            for (size_t level = 0; level < table.levels.size(); ++level) {
                filtered = spectrum;
                filtered[0] = 0; // Remove DC offset from user cycles.
                const int limit = table.harmonicLimits[level];
                for (int bin = 1; bin < frame_size; ++bin)
                    if (std::min(bin, frame_size - bin) > limit) filtered[bin] = 0;
                fft(filtered, true);
                for (int i = 0; i < frame_size; ++i)
                    table.levels[level][frame * frame_size + i] = static_cast<float>(filtered[i].real());
            }
        }
        engine->importedTables[oscillator] = std::move(table);
        return 1;
    } catch (...) { return 0; }
}

int sd_generate_wavetable(float *output, int sample_count, int frame_size,
                          unsigned int seed) {
    // Validate before arithmetic or writes, including adversarial signed counts.
    if (!output || frame_size < 32 || frame_size > 2048 ||
        (frame_size & (frame_size - 1)) || sample_count <= 0 ||
        sample_count % frame_size) return 0;
    const int frames = sample_count / frame_size;
    if (frames < 2 || frames > 256) return 0;
    try {
        constexpr int anchors = 5, maxHarmonics = 32;
        const int harmonics = std::min(maxHarmonics, frame_size / 2 - 1);
        uint32_t random = seed ? static_cast<uint32_t>(seed) : 0x9e3779b9u;
        std::array<double, maxHarmonics> phases{}, detail{};
        for (int h = 1; h <= harmonics; ++h) {
            // A common phase per partial preserves shape when POSITION morphs.
            phases[h - 1] = h == 1 ? 0 : (randomUnit(random) - .5) * .24;
            detail[h - 1] = .7 + .6 * randomUnit(random);
        }
        std::array<std::array<double, maxHarmonics>, anchors> spectra{};
        for (auto &spectrum : spectra) {
            const double tilt = .85 + .9 * randomUnit(random);
            const double odd = .4 + .65 * randomUnit(random);
            const double even = .08 + .85 * randomUnit(random);
            const double center = 2 + (harmonics - 2) * randomUnit(random);
            const double secondCenter = 2 + (harmonics - 2) * randomUnit(random);
            const double width = 1 + 2.5 * randomUnit(random);
            const double formant = .45 + .8 * randomUnit(random);
            const double secondFormant = .1 + .4 * randomUnit(random);
            spectrum[0] = .9 + .3 * randomUnit(random);
            for (int h = 2; h <= harmonics; ++h) {
                const double d = (h - center) / width;
                const double d2 = (h - secondCenter) / (width * 1.4);
                spectrum[h - 1] = detail[h - 1] * (
                    (h % 2 ? odd : even) / std::pow(h, tilt) +
                    (formant * std::exp(-.5 * d * d) +
                     secondFormant * std::exp(-.5 * d2 * d2)) / std::sqrt(h));
            }
        }
        // Precompute cycles once so larger banks do not repeat trigonometry.
        std::vector<std::array<double, maxHarmonics>> cycles(frame_size);
        for (int i = 0; i < frame_size; ++i)
            for (int h = 1; h <= harmonics; ++h)
                cycles[i][h - 1] = std::sin(2 * kPi *
                    (static_cast<double>(i) * h / frame_size + phases[h - 1]));
        std::vector<float> bank(static_cast<size_t>(sample_count));
        double peak = 0;
        for (int frame = 0; frame < frames; ++frame) {
            const double position = static_cast<double>(frame) * (anchors - 1) / (frames - 1);
            const int a = std::min(static_cast<int>(position), anchors - 2);
            const double fraction = position - a;
            const double blend = fraction * fraction * (3 - 2 * fraction);
            std::array<double, maxHarmonics> amplitudes{};
            for (int h = 0; h < harmonics; ++h)
                amplitudes[h] = spectra[a][h] + (spectra[a + 1][h] - spectra[a][h]) * blend;
            double sum = 0;
            for (int i = 0; i < frame_size; ++i) {
                double value = 0;
                for (int h = 0; h < harmonics; ++h) value += amplitudes[h] * cycles[i][h];
                bank[frame * frame_size + i] = static_cast<float>(value);
                sum += bank[frame * frame_size + i];
            }
            // Analytical sine cycles have no DC; remove float rounding residue.
            const double mean = sum / frame_size;
            for (int i = 0; i < frame_size; ++i) {
                auto &value = bank[frame * frame_size + i];
                value = static_cast<float>(value - mean);
                peak = std::max(peak, std::abs(static_cast<double>(value)));
            }
        }
        if (!std::isfinite(peak) || peak <= 0) return 0;
        const double gain = .949999 / peak;
        for (int i = 0; i < sample_count; ++i)
            output[i] = static_cast<float>(bank[i] * gain);
        return 1;
    } catch (...) { return 0; }
}
}
