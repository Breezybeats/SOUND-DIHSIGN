import SwiftUI
import UniformTypeIdentifiers

private enum SynthPalette {
    static let background = Color(red: 0.035, green: 0.052, blue: 0.085)
    static let panel = Color(red: 0.067, green: 0.090, blue: 0.135)
    static let raised = Color(red: 0.105, green: 0.133, blue: 0.185)
    static let line = Color(red: 0.18, green: 0.22, blue: 0.29)
    static let text = Color(red: 0.92, green: 0.95, blue: 0.98)
    static let muted = Color(red: 0.54, green: 0.62, blue: 0.72)
    static let mint = Color(red: 0.35, green: 0.94, blue: 0.78)
    static let violet = Color(red: 0.66, green: 0.54, blue: 1)
    static let gold = Color(red: 1, green: 0.75, blue: 0.39)
}

@MainActor
struct SynthView: View {
    @ObservedObject var model: SynthModel
    @State private var confirmingReset = false

    private var oscillatorBase: Int { model.selectedOscillator * 32 }
    private var oscillatorMode: Int { Int(model.value(oscillatorBase)) }
    private var sourceName: String { sourceTitle(model.selectedSource) }
    private var customWavetableLoaded: Bool { model.patch.wavetables.contains { $0.oscillator == model.selectedOscillator } }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                pageTabs
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        patchTitle
                        switch model.selectedPage {
                        case .oscillator: oscillatorPage
                        case .filter: filterPage
                        case .envelopes: envelopePage
                        case .effects: effectsPage
                        case .modulation: modulationPage
                        }
                        modulationSources
                        if !model.status.isEmpty {
                            Text(model.status)
                                .font(.caption)
                                .foregroundStyle(SynthPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                }
                keyboard(height: geometry.size.height < 500 ? 82 : 114)
            }
            .background(SynthPalette.background)
            .foregroundStyle(SynthPalette.text)
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("Create a new patch?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Create new patch", role: .destructive) { model.resetPatch() }
        } message: {
            Text("Export the current patch first if you want to keep it.")
        }
        .onDisappear { model.allNotesOff() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    Text("SOUND").foregroundStyle(SynthPalette.text)
                    Text("/").foregroundStyle(SynthPalette.mint)
                    Text("DIHSIGN").foregroundStyle(SynthPalette.text)
                }
                .font(.system(size: 16, weight: .black, design: .rounded))
                .tracking(1.3)
                HStack(spacing: 5) {
                    Circle().fill(model.audioReady ? SynthPalette.mint : SynthPalette.muted).frame(width: 5, height: 5)
                    Text(model.audioReady ? "ORIGINAL ENGINE · LIVE" : "ORIGINAL ENGINE · AUDIO OFF")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SynthPalette.muted)
                }
            }
            Spacer(minLength: 0)
            Button {
                if model.audioReady { model.stopAudio() } else { model.startAudio() }
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(model.audioReady ? SynthPalette.mint : SynthPalette.muted)
                    .frame(width: 42, height: 42)
                    .background(SynthPalette.raised, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel(model.audioReady ? "Stop audio" : "Start audio")
            Menu {
                Button("New patch", systemImage: "plus") { confirmingReset = true }
                Button("Import SOUND/DIHSIGN patch", systemImage: "square.and.arrow.down") { model.isImportingPatch = true }
                Button("Export SOUND/DIHSIGN patch", systemImage: "square.and.arrow.up") { model.isExportingPatch = true }
                Button("Release all notes", systemImage: "hand.raised") { model.allNotesOff() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(SynthPalette.raised, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Patch actions")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 13)
    }

    private var pageTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(SynthPage.allCases, id: \.self) { page in
                    Button { model.selectedPage = page } label: {
                        HStack(spacing: 5) {
                            Image(systemName: pageIcon(page)).font(.system(size: 11, weight: .semibold))
                            Text(pageTitle(page)).font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .foregroundStyle(model.selectedPage == page ? SynthPalette.background : SynthPalette.muted)
                        .background(model.selectedPage == page ? SynthPalette.mint : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .accessibilityAddTraits(model.selectedPage == page ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(SynthPalette.background)
        .overlay(alignment: .bottom) { Rectangle().fill(SynthPalette.line.opacity(0.6)).frame(height: 1) }
    }

    private var patchTitle: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CURRENT PATCH")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(SynthPalette.muted)
                TextField("Patch name", text: $model.patch.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .submitLabel(.done)
                    .accessibilityLabel("Patch name")
            }
            Spacer(minLength: 0)
            Button { model.isExportingPatch = true } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SynthPalette.mint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(SynthPalette.mint.opacity(0.10), in: Capsule())
                    .overlay(Capsule().stroke(SynthPalette.mint.opacity(0.24)))
            }
            .accessibilityHint("Exports the app's native patch format")
        }
    }

    private var oscillatorPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Button { model.selectedOscillator = index } label: {
                        HStack(spacing: 7) {
                            Circle().fill(model.selectedOscillator == index ? SynthPalette.mint : SynthPalette.muted).frame(width: 5, height: 5)
                            Text("OSC \(["A", "B", "C"][index])")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(model.selectedOscillator == index ? SynthPalette.text : SynthPalette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(model.selectedOscillator == index ? SynthPalette.raised : SynthPalette.panel, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.selectedOscillator == index ? SynthPalette.mint.opacity(0.55) : SynthPalette.line.opacity(0.5)))
                    }
                    .accessibilityAddTraits(model.selectedOscillator == index ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    sectionLabel("OSCILLATOR ENGINE", icon: "waveform")
                    Spacer()
                    Text(["WAVETABLE", "SAMPLE", "GRANULAR", "SPECTRAL"][min(3, max(0, oscillatorMode))])
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SynthPalette.mint)
                }
                Picker("Oscillator engine", selection: Binding(get: { oscillatorMode }, set: { model.set(oscillatorBase, Float($0)) })) {
                    Text("Wave").tag(0)
                    Text("Sample").tag(1)
                    Text("Grain").tag(2)
                    Text("Spectral").tag(3)
                }
                .pickerStyle(.segmented)
                .tint(SynthPalette.mint)
                if oscillatorMode == 0 {
                    wavetableSelector
                    SynthWaveform(table: Int(model.value(oscillatorBase + 1)), position: model.value(oscillatorBase + 2), warp: model.value(oscillatorBase + 9), customTable: model.patch.wavetables.first { $0.oscillator == model.selectedOscillator })
                        .frame(height: 96)
                        .background(SynthPalette.background, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .bottomTrailing) {
                            Text("SHAPE PREVIEW")
                                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                                .foregroundStyle(SynthPalette.muted)
                                .padding(8)
                        }
                        .accessibilityLabel("Wavetable shape preview")
                } else {
                    samplePanel
                }
                knobGrid(oscillatorControls, tint: SynthPalette.mint)
            }
            .synthPanel()
            HStack(spacing: 16) {
                SynthKnob(model: model, id: 138, title: "Sub", tint: SynthPalette.gold)
                SynthKnob(model: model, id: 139, title: "Noise", tint: SynthPalette.gold)
                VStack(alignment: .leading, spacing: 6) {
                    Text("THE FOUNDATION").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(SynthPalette.gold)
                    Text("Add a clean sub or a little noise texture beneath your oscillators.")
                        .font(.caption)
                        .foregroundStyle(SynthPalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .synthPanel()
        }
    }

    private var wavetableSelector: some View {
        VStack(alignment: .leading, spacing: 9) {
          Menu {
            ForEach(Array(["Basic", "Growl", "Hollow"].enumerated()), id: \.offset) { index, title in
                Button { model.selectTable(index, oscillator: model.selectedOscillator) } label: {
                    if !customWavetableLoaded && Int(model.value(oscillatorBase + 1)) == index {
                        Label(title, systemImage: "checkmark")
                    } else { Text(title) }
                }
            }
        } label: {
            HStack {
                Image(systemName: "square.stack.3d.up").foregroundStyle(SynthPalette.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(customWavetableLoaded ? "Custom imported table" : ["Basic", "Growl", "Hollow"][min(2, max(0, Int(model.value(oscillatorBase + 1))))])
                        .font(.system(size: 14, weight: .semibold))
                    Text(customWavetableLoaded ? "Embedded in your patch" : "Built-in original wavetable").font(.system(size: 10)).foregroundStyle(SynthPalette.muted)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(SynthPalette.muted)
            }
            .padding(12)
            .background(SynthPalette.raised.opacity(0.75), in: RoundedRectangle(cornerRadius: 9))
        }
          .accessibilityLabel("Choose wavetable")
          Button {
              model.wavetableImportOscillator = model.selectedOscillator
              model.isImportingWavetable = true
          } label: {
              Label("Import table WAV", systemImage: "square.and.arrow.down")
                  .font(.system(size: 11, weight: .semibold))
                  .foregroundStyle(SynthPalette.mint)
          }
          Text("Mono WAV · 2,048 samples per frame · up to 256 frames")
              .font(.system(size: 9))
              .foregroundStyle(SynthPalette.muted)
        }
    }

    private var samplePanel: some View {
        let loaded = model.patch.samples.contains { $0.oscillator == model.selectedOscillator }
        let usingTable = oscillatorMode == 3 && customWavetableLoaded
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: oscillatorMode == 2 ? "sparkles" : "waveform.path")
                    .font(.system(size: 22))
                    .foregroundStyle(SynthPalette.violet)
                VStack(alignment: .leading, spacing: 3) {
                    Text(usingTable ? "Imported table harmonics" : loaded ? "Audio loaded" : "Bring your own texture")
                        .font(.system(size: 14, weight: .semibold))
                    Text(usingTable ? "Additive resynthesis of the custom table." : sampleExplanation)
                        .font(.system(size: 11))
                        .foregroundStyle(SynthPalette.muted)
                }
                Spacer(minLength: 0)
            }
            Button {
                model.sampleImportOscillator = model.selectedOscillator
                model.isImportingSample = true
            } label: {
                Label(usingTable ? "Use imported audio instead" : loaded ? "Replace audio" : "Import audio", systemImage: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(SynthPalette.violet)
                    .background(SynthPalette.violet.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .padding(12)
        .background(SynthPalette.background, in: RoundedRectangle(cornerRadius: 10))
    }

    private var sampleExplanation: String {
        switch oscillatorMode {
        case 1: return "Play an imported one-shot across the keyboard."
        case 2: return "Turn imported audio into overlapping grains."
        default: return "Additive harmonic resynthesis of imported audio."
        }
    }

    private var oscillatorControls: [KnobSpec] {
        let base = oscillatorBase
        var controls = [KnobSpec(id: base + 3, title: "Level"), KnobSpec(id: base + 4, title: "Semi"), KnobSpec(id: base + 5, title: "Fine"), KnobSpec(id: base + 8, title: "Pan")]
        switch oscillatorMode {
        case 0:
            controls += [KnobSpec(id: base + 2, title: "Position"), KnobSpec(id: base + 9, title: "Warp"), KnobSpec(id: base + 6, title: "Unison"), KnobSpec(id: base + 7, title: "Detune")]
        case 1:
            controls += [KnobSpec(id: base + 2, title: "Start"), KnobSpec(id: base + 9, title: "Warp"), KnobSpec(id: base + 6, title: "Unison"), KnobSpec(id: base + 7, title: "Detune")]
        case 2:
            controls += [KnobSpec(id: base + 2, title: "Position"), KnobSpec(id: base + 10, title: "Scan"), KnobSpec(id: base + 11, title: "Size"), KnobSpec(id: base + 12, title: "Density"), KnobSpec(id: base + 9, title: "Warp"), KnobSpec(id: base + 6, title: "Unison"), KnobSpec(id: base + 7, title: "Detune")]
        default:
            controls += [KnobSpec(id: base + 2, title: "Shape"), KnobSpec(id: base + 9, title: "Warp"), KnobSpec(id: base + 6, title: "Unison"), KnobSpec(id: base + 7, title: "Detune")]
        }
        return controls
    }

    private var filterPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("FILTER", icon: "line.3.horizontal.decrease")
            Text("Shape the space around your sound.")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text("A resonant low-pass filter after the oscillator mix.")
                .font(.caption).foregroundStyle(SynthPalette.muted)
            SynthFilterPlot(cutoff: model.value(128), resonance: model.value(129))
                .frame(height: 128)
                .background(SynthPalette.background, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Low-pass response illustration")
            HStack(spacing: 30) {
                SynthKnob(model: model, id: 128, title: "Cutoff", tint: SynthPalette.mint, diameter: 76)
                SynthKnob(model: model, id: 129, title: "Resonance", tint: SynthPalette.mint, diameter: 76)
            }
            .frame(maxWidth: .infinity)
            Text("Try linking LFO 1 to Cutoff for movement.")
                .font(.caption).foregroundStyle(SynthPalette.muted)
        }
        .synthPanel()
    }

    private var envelopePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("ENV 1 · AMPLITUDE", icon: "chart.xyaxis.line")
            SynthEnvelopePlot(attack: model.value(134), decay: model.value(135), sustain: model.value(136), release: model.value(137))
                .frame(height: 118)
                .background(SynthPalette.background, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Attack decay sustain release envelope")
            knobGrid([KnobSpec(id: 134, title: "Attack"), KnobSpec(id: 135, title: "Decay"), KnobSpec(id: 136, title: "Sustain"), KnobSpec(id: 137, title: "Release")], tint: SynthPalette.violet)
            Divider().overlay(SynthPalette.line)
            sectionLabel("LFO 1 · SINE", icon: "waveform.path")
            HStack(spacing: 18) {
                SynthKnob(model: model, id: 132, title: "Rate", tint: SynthPalette.violet, diameter: 68)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Make it move.").font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Drag LFO 1 onto a knob, then open Routes to tune its modulation depth.")
                        .font(.caption).foregroundStyle(SynthPalette.muted)
                }
            }
        }
        .synthPanel()
    }

    private var effectsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            effectCard(title: "DRIVE", subtitle: "Add saturation and harmonic weight.", icon: "bolt.fill", id: 130, color: SynthPalette.gold)
            effectCard(title: "DELAY", subtitle: "Blend in echoes after the filter and drive.", icon: "repeat", id: 131, color: SynthPalette.violet)
            Text("This engine currently includes drive and delay. More effects can be added as the engine develops.")
                .font(.caption)
                .foregroundStyle(SynthPalette.muted)
        }
    }

    private func effectCard(title: String, subtitle: String, icon: String, id: Int, color: Color) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(color)
                Text(title).font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(1.5)
                Text(subtitle).font(.caption).foregroundStyle(SynthPalette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SynthKnob(model: model, id: id, title: id == 130 ? "Amount" : "Mix", tint: color, diameter: 72)
        }
        .synthPanel()
    }

    private var modulationPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionLabel("MODULATION ROUTES", icon: "point.3.connected.trianglepath.dotted")
                Spacer()
                Text("\(model.patch.routes.count)").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(SynthPalette.violet)
            }
            if model.patch.routes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "arrow.up.right").font(.system(size: 24, weight: .light)).foregroundStyle(SynthPalette.violet)
                    Text("Give your sound some motion.").font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Choose a source below, then tap the link symbol on a knob. You can also drag a source directly onto a knob.")
                        .font(.caption).foregroundStyle(SynthPalette.muted)
                }
                .padding(.vertical, 12)
            } else {
                ForEach(model.patch.routes, id: \.slot) { route in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 7) {
                            Text(sourceTitle(route.source)).foregroundStyle(SynthPalette.violet)
                            Image(systemName: "arrow.right").foregroundStyle(SynthPalette.muted)
                            Text(ParameterCatalog.name(route.destination))
                            Spacer(minLength: 0)
                            Button { model.removeRoute(slot: route.slot) } label: {
                                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).padding(9)
                                    .background(SynthPalette.background, in: Circle())
                            }
                            .accessibilityLabel("Remove \(sourceTitle(route.source)) to \(ParameterCatalog.name(route.destination)) route")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        HStack(spacing: 10) {
                            Slider(value: Binding(get: { route.amount }, set: { model.setRouteAmount(slot: route.slot, amount: $0) }), in: -1...1)
                                .tint(SynthPalette.violet)
                                .accessibilityLabel("Modulation depth")
                            Text(String(format: "%+.0f%%", route.amount * 100))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(SynthPalette.muted)
                                .frame(width: 45, alignment: .trailing)
                        }
                    }
                    .padding(12)
                    .background(SynthPalette.raised.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Divider().overlay(SynthPalette.line)
            HStack(spacing: 18) {
                SynthKnob(model: model, id: 140, title: "Macro 1", tint: SynthPalette.gold, diameter: 68)
                Text("Link Macro 1 to several destinations to shape your patch with one control.")
                    .font(.caption).foregroundStyle(SynthPalette.muted)
            }
        }
        .synthPanel()
    }

    private var modulationSources: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("MOD SOURCES").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.4)
                Spacer()
                Button { model.selectedPage = .modulation } label: {
                    HStack(spacing: 4) {
                        Text("Routes \(model.patch.routes.count)")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SynthPalette.violet)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...4, id: \.self) { source in
                        Button { model.selectedSource = source } label: {
                            HStack(spacing: 5) {
                                Image(systemName: sourceIcon(source))
                                Text(sourceTitle(source))
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(model.selectedSource == source ? SynthPalette.background : SynthPalette.violet)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 10)
                            .background(model.selectedSource == source ? SynthPalette.violet : SynthPalette.violet.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                        }
                        .onDrag { NSItemProvider(object: "sounddihsign:source:\(source)" as NSString) }
                        .accessibilityAddTraits(model.selectedSource == source ? .isSelected : [])
                        .accessibilityHint("Select, then tap a knob's link button")
                    }
                }
            }
            Text("Drag to a knob, or select \(sourceName) and tap a knob’s link symbol.")
                .font(.system(size: 10))
                .foregroundStyle(SynthPalette.muted)
        }
        .synthPanel()
    }

    private func keyboard(height: CGFloat) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "pianokeys").font(.system(size: 12)).foregroundStyle(SynthPalette.mint)
                Button {
                    model.allNotesOff()
                    model.octave = max(0, model.octave - 1)
                } label: { Image(systemName: "minus").font(.system(size: 10, weight: .bold)).frame(width: 28, height: 28).background(SynthPalette.raised, in: RoundedRectangle(cornerRadius: 7)) }
                .accessibilityLabel("Lower keyboard one octave")
                .disabled(model.octave <= 0)
                Text("OCT \(model.octave)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(SynthPalette.muted)
                Button {
                    model.allNotesOff()
                    model.octave = min(7, model.octave + 1)
                } label: { Image(systemName: "plus").font(.system(size: 10, weight: .bold)).frame(width: 28, height: 28).background(SynthPalette.raised, in: RoundedRectangle(cornerRadius: 7)) }
                .accessibilityLabel("Raise keyboard one octave")
                .disabled(model.octave >= 7)
                Spacer(minLength: 0)
                Image(systemName: "speaker.wave.2").font(.system(size: 11)).foregroundStyle(SynthPalette.muted)
                Slider(value: Binding(get: { model.value(133) }, set: { model.set(133, $0) }), in: 0...1)
                    .tint(SynthPalette.mint)
                    .frame(width: 72)
                    .accessibilityLabel("Master level")
            }
            TouchKeyboard(baseNote: (model.octave + 1) * 12, onNoteOn: { note, velocity in model.noteOn(note, velocity: velocity) }, onNoteOff: { model.noteOff($0) })
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(SynthPalette.background)
        .overlay(alignment: .top) { Rectangle().fill(SynthPalette.line).frame(height: 1) }
    }

    private func knobGrid(_ controls: [KnobSpec], tint: Color) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 67), spacing: 12)], spacing: 17) {
            ForEach(controls) { spec in SynthKnob(model: model, id: spec.id, title: spec.title, tint: tint) }
        }
    }

    private func sectionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(SynthPalette.mint)
            Text(title).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.3)
        }
    }

    private func pageTitle(_ page: SynthPage) -> String {
        switch page {
        case .oscillator: return "Oscillators"
        case .filter: return "Filter"
        case .envelopes: return "Motion"
        case .effects: return "FX"
        case .modulation: return "Routes"
        }
    }

    private func pageIcon(_ page: SynthPage) -> String {
        switch page {
        case .oscillator: return "waveform"
        case .filter: return "line.3.horizontal.decrease"
        case .envelopes: return "chart.xyaxis.line"
        case .effects: return "sparkles"
        case .modulation: return "point.3.connected.trianglepath.dotted"
        }
    }
}

private struct KnobSpec: Identifiable {
    let id: Int
    let title: String
}

@MainActor
private struct SynthKnob: View {
    @ObservedObject var model: SynthModel
    let id: Int
    let title: String
    let tint: Color
    var diameter: CGFloat = 54
    @State private var dragStart: Float?
    @State private var dropTarget = false

    private var range: ClosedRange<Float> { ParameterCatalog.descriptor(id)?.range ?? 0...1 }
    private var discrete: Bool { ParameterCatalog.descriptor(id)?.isDiscrete ?? false }
    private var logarithmic: Bool { [128, 132, 134, 135, 137].contains(id) || id < 96 && [11, 12].contains(id % 32) }
    private var hasRoute: Bool { model.patch.routes.contains { $0.destination == id } }
    private var normalized: Float {
        let value = min(range.upperBound, max(range.lowerBound, model.value(id)))
        if logarithmic && range.lowerBound > 0 {
            return log(value / range.lowerBound) / log(range.upperBound / range.lowerBound)
        }
        return (value - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                if !discrete {
                  Button { model.route(source: model.selectedSource, destination: id) } label: {
                    Image(systemName: "link")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(hasRoute ? SynthPalette.violet : SynthPalette.muted)
                        .frame(width: 21, height: 24)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Link \(sourceTitle(model.selectedSource)) to \(ParameterCatalog.name(id))")
                }
            }
            ZStack {
                Circle().trim(from: 0, to: 0.75).stroke(SynthPalette.line, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(135))
                Circle().trim(from: 0, to: CGFloat(normalized) * 0.75).stroke(dropTarget ? SynthPalette.violet : tint, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(135))
                Circle().fill(LinearGradient(colors: [SynthPalette.raised, SynthPalette.panel], startPoint: .topLeading, endPoint: .bottomTrailing)).padding(7)
                Circle().stroke(SynthPalette.line.opacity(0.5), lineWidth: 1).padding(7)
                Capsule().fill(SynthPalette.text).frame(width: 2, height: diameter * 0.19).offset(y: -diameter * 0.22).rotationEffect(.degrees(-135 + Double(normalized) * 270))
                if hasRoute {
                    Circle().fill(SynthPalette.violet).frame(width: 4, height: 4).offset(y: diameter * 0.38)
                }
            }
            .frame(width: diameter, height: diameter)
            .padding(3)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { gesture in
                    if dragStart == nil { dragStart = normalized }
                    applyNormalized((dragStart ?? normalized) - Float(gesture.translation.height) / 160)
                }
                .onEnded { _ in dragStart = nil })
            .onDrop(of: [UTType.plainText], isTargeted: $dropTarget) { providers in
                guard !discrete, let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let token = object as? String, token.hasPrefix("sounddihsign:source:"),
                          let source = Int(token.split(separator: ":").last ?? ""), (1...4).contains(source) else { return }
                    DispatchQueue.main.async { model.route(source: source, destination: id) }
                }
                return true
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ParameterCatalog.name(id))
            .accessibilityValue(displayValue)
            .accessibilityHint("Swipe up or down to adjust")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: adjustAccessibility(up: true)
                case .decrement: adjustAccessibility(up: false)
                @unknown default: break
                }
            }
            .contextMenu {
                if !discrete {
                    Button("Link \(sourceTitle(model.selectedSource))", systemImage: "link") { model.route(source: model.selectedSource, destination: id) }
                }
                Button("Reset \(title)", systemImage: "arrow.counterclockwise") {
                    if let descriptor = ParameterCatalog.descriptor(id) { model.set(id, descriptor.defaultValue) }
                }
            }
            Text(displayValue)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(SynthPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func applyNormalized(_ fraction: Float) {
        let value = min(1, max(0, fraction))
        let result: Float
        if logarithmic && range.lowerBound > 0 {
            result = range.lowerBound * pow(range.upperBound / range.lowerBound, value)
        } else {
            result = range.lowerBound + value * (range.upperBound - range.lowerBound)
        }
        model.set(id, discrete ? result.rounded() : result)
    }

    private func adjustAccessibility(up: Bool) {
        if discrete {
            model.set(id, min(range.upperBound, max(range.lowerBound, model.value(id) + (up ? 1 : -1))))
        } else { applyNormalized(normalized + (up ? 0.025 : -0.025)) }
    }

    private var displayValue: String {
        let value = model.value(id)
        if id == 128 { return value >= 1000 ? String(format: "%.2f kHz", value / 1000) : String(format: "%.0f Hz", value) }
        if id == 132 { return String(format: "%.2f Hz", value) }
        if [134, 135, 137].contains(id) || id < 96 && id % 32 == 11 {
            return value < 1 ? String(format: "%.0f ms", value * 1000) : String(format: "%.2f s", value)
        }
        if id < 96 {
            switch id % 32 {
            case 4: return String(format: "%+.0f st", value)
            case 5: return String(format: "%+.0f ct", value)
            case 6: return String(format: "%.0f voices", value)
            case 8:
                if abs(value - 0.5) < 0.01 { return "Center" }
                return String(format: "%.0f%% %@", abs(value - 0.5) * 200, value < 0.5 ? "L" : "R")
            case 12: return String(format: "%.0f /s", value)
            default: break
            }
        }
        return String(format: "%.0f%%", value * 100)
    }
}

private struct SynthWaveform: View {
    var table: Int
    var position: Float
    var warp: Float
    var customTable: WavetableAsset?

    var body: some View {
        Canvas { context, size in
            drawGrid(context: context, size: size)
            var line = Path()
            for sample in 0...240 {
                let phase = Double(sample) / 240 * 2
                let shaped = phase + sin(phase * .pi * 2) * Double(warp) * 0.14
                let value = sampleValue(phase: shaped)
                let point = CGPoint(x: Double(sample) / 240 * size.width, y: size.height / 2 - value * size.height * 0.34)
                if sample == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            context.stroke(line, with: .color(SynthPalette.mint.opacity(0.10)), lineWidth: 8)
            context.stroke(line, with: .color(SynthPalette.mint), lineWidth: 1.6)
        }
    }

    private func sampleValue(phase: Double) -> Double {
        let p = Double(min(1, max(0, position)))
        if let customTable, customTable.frameSize > 0, !customTable.samples.isEmpty {
            let length = customTable.frameSize
            let count = customTable.samples.count / length
            guard count > 0 else { return 0 }
            let frame = p * Double(count - 1)
            let first = Int(frame), second = min(first + 1, count - 1)
            let frameMix = frame - Double(first)
            let index = (phase - floor(phase)) * Double(length)
            let i = Int(index), j = (i + 1) % length
            let sampleMix = index - Double(i)
            let a = Double(customTable.samples[first * length + i]) * (1 - sampleMix) + Double(customTable.samples[first * length + j]) * sampleMix
            let b = Double(customTable.samples[second * length + i]) * (1 - sampleMix) + Double(customTable.samples[second * length + j]) * sampleMix
            return a + frameMix * (b - a)
        }
        let frame = p * 3
        let first = min(2, Int(frame)), mix = frame - Double(first)
        let frames = SynthPreviewTables.spectra[min(2, max(0, table))]
        var value = 0.0
        for harmonic in 1...24 {
            let a = frames[first][harmonic - 1], b = frames[first + 1][harmonic - 1]
            value += (a + mix * (b - a)) * sin(phase * Double(harmonic) * .pi * 2)
        }
        return value
    }
}

/// Dry table previews use the same harmonic recipes as the original C++ engine.
private enum SynthPreviewTables {
    static let spectra: [[[Double]]] = makeSpectra()

    private static func makeSpectra() -> [[[Double]]] {
        var result: [[[Double]]] = []
        for table in 0..<3 {
            var frames: [[Double]] = []
            for frame in 0..<4 {
                var amplitudes = [Double](repeating: 0, count: 24)
                for harmonic in 1...24 {
                    let h = Double(harmonic)
                    let amplitude: Double
                    if table == 0 {
                        switch frame {
                        case 0: amplitude = harmonic == 1 ? 1 : 0
                        case 1: amplitude = 1 / h
                        case 2: amplitude = harmonic % 2 == 1 ? 1 / h : 0
                        default: amplitude = harmonic % 2 == 1 ? (harmonic % 4 == 1 ? 1 : -1) / (h * h) : 0
                        }
                    } else if table == 1 {
                        let center = 3 + Double(frame) * 3.5
                        let raw = (harmonic == 1 ? 0.65 : 0) + exp(-0.08 * pow(h - center, 2)) / sqrt(h)
                        amplitude = harmonic % 3 == 0 ? raw * 0.25 : raw
                    } else {
                        let center = 5 + Double(frame) * 4
                        amplitude = harmonic % 2 == 1 ? 0.8 / h + 0.6 * exp(-0.16 * pow(h - center, 2)) : 0.04 / h
                    }
                    amplitudes[harmonic - 1] = amplitude
                }
                var maximum = 0.001
                for sample in 0..<2048 {
                    let phase = Double(sample) / 2048 * .pi * 2
                    var value = 0.0
                    for harmonic in 1...24 { value += amplitudes[harmonic - 1] * sin(phase * Double(harmonic)) }
                    maximum = max(maximum, abs(value))
                }
                frames.append(amplitudes.map { $0 / maximum })
            }
            result.append(frames)
        }
        return result
    }
}

private struct SynthEnvelopePlot: View {
    var attack: Float
    var decay: Float
    var sustain: Float
    var release: Float

    var body: some View {
        Canvas { context, size in
            drawGrid(context: context, size: size)
            let margin: CGFloat = 15
            let usableWidth = size.width - margin * 2
            let usableHeight = size.height - margin * 2
            let a = CGFloat(sqrt(max(0.001, attack)))
            let d = CGFloat(sqrt(max(0.001, decay)))
            let r = CGFloat(sqrt(max(0.001, release)))
            let total = a + d + r + 1
            let bottom = size.height - margin
            let sustainY = bottom - usableHeight * CGFloat(sustain)
            var line = Path()
            line.move(to: CGPoint(x: margin, y: bottom))
            line.addLine(to: CGPoint(x: margin + usableWidth * a / total, y: margin))
            line.addLine(to: CGPoint(x: margin + usableWidth * (a + d) / total, y: sustainY))
            line.addLine(to: CGPoint(x: margin + usableWidth * (a + d + 1) / total, y: sustainY))
            line.addLine(to: CGPoint(x: size.width - margin, y: bottom))
            context.stroke(line, with: .color(SynthPalette.violet.opacity(0.13)), lineWidth: 9)
            context.stroke(line, with: .color(SynthPalette.violet), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
    }
}

private struct SynthFilterPlot: View {
    var cutoff: Float
    var resonance: Float

    var body: some View {
        Canvas { context, size in
            drawGrid(context: context, size: size)
            let knee = CGFloat(log(max(20, cutoff) / 20) / log(1000)) * size.width * 0.8 + size.width * 0.1
            var line = Path()
            for index in 0...160 {
                let x = CGFloat(index) / 160 * size.width
                let drop = max(0, (x - knee) / max(1, size.width - knee))
                let bump = exp(-pow((x - knee) / max(10, size.width * 0.045), 2)) * CGFloat(resonance) * size.height * 0.24
                let y = min(size.height - 12, size.height * 0.43 + drop * size.height * 0.6 - bump)
                if index == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(line, with: .color(SynthPalette.mint.opacity(0.12)), lineWidth: 8)
            context.stroke(line, with: .color(SynthPalette.mint), lineWidth: 2)
        }
    }
}

private func drawGrid(context: GraphicsContext, size: CGSize) {
    var grid = Path()
    for index in 1..<8 {
        let x = size.width * CGFloat(index) / 8
        grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
    }
    for index in 1..<4 {
        let y = size.height * CGFloat(index) / 4
        grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
    }
    context.stroke(grid, with: .color(SynthPalette.line.opacity(0.4)), lineWidth: 0.5)
}

private func sourceTitle(_ source: Int) -> String {
    switch source {
    case 1: return "LFO 1"
    case 2: return "Env 1"
    case 3: return "Velocity"
    case 4: return "Macro 1"
    default: return "Source \(source)"
    }
}

private func sourceIcon(_ source: Int) -> String {
    switch source {
    case 1: return "waveform.path"
    case 2: return "chart.xyaxis.line"
    case 3: return "hand.tap"
    default: return "dial.low"
    }
}

private extension View {
    func synthPanel() -> some View {
        padding(15)
            .background(SynthPalette.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(SynthPalette.line.opacity(0.55)))
    }
}
