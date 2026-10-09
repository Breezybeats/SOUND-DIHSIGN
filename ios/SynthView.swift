import SwiftUI
import UniformTypeIdentifiers

private enum SynthPalette {
    static let background = Color.white
    static let panel = Color(red: 0.965, green: 0.97, blue: 0.98)
    static let raised = Color.white
    static let line = Color(red: 0.85, green: 0.87, blue: 0.9)
    static let text = Color(red: 0.1, green: 0.12, blue: 0.16)
    static let muted = Color(red: 0.37, green: 0.40, blue: 0.45)
    static let mint = Color(red: 0.0, green: 0.36, blue: 0.88)
    static let violet = mint
    static let gold = mint
}

@MainActor
struct SynthView: View {
    @ObservedObject var model: SynthModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingReset = false
    @State private var showingAdvanced = false
    @State private var showingModulation = false

    private var oscillatorBase: Int { model.selectedOscillator * 32 }
    private var oscillatorMode: Int { Int(model.value(oscillatorBase)) }
    private var customWavetable: WavetableAsset? { model.patch.wavetables.first { $0.oscillator == model.selectedOscillator } }
    private var customWavetableLoaded: Bool { customWavetable != nil }
    private var transitionAnimation: Animation? { reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.88) }
    private var tableTitle: String {
        if customWavetableLoaded { return model.generatedWavetableNames[model.selectedOscillator] ?? "Custom wavetable" }
        return ["Basic", "Growl", "Hollow"][min(2, max(0, Int(model.value(oscillatorBase + 1))))]
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                pageTabs
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch model.selectedPage {
                        case .oscillator: oscillatorPage
                        case .filter: filterPage
                        case .envelopes: envelopePage
                        case .effects: effectsPage
                        case .modulation: modulationPage
                        }
                        if model.selectedPage != .modulation {
                            DisclosureGroup("Modulation", isExpanded: $showingModulation) {
                                modulationSources.padding(.top, 12)
                            }
                            .font(.subheadline.weight(.medium))
                            .tint(SynthPalette.mint)
                            .padding(.vertical, 8)
                        }
                        if !model.status.isEmpty {
                            Text(model.status)
                                .font(.caption)
                                .foregroundStyle(SynthPalette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Status: \(model.status)")
                        }
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                    .animation(transitionAnimation, value: model.selectedPage)
                    .animation(transitionAnimation, value: model.selectedOscillator)
                    .animation(transitionAnimation, value: showingAdvanced)
                    .animation(transitionAnimation, value: showingModulation)
                }
                .scrollDismissesKeyboard(.interactively)
                keyboard(height: geometry.size.height < 500 ? 72 : 108)
            }
            .background(SynthPalette.background)
            .foregroundStyle(SynthPalette.text)
        }
        .tint(SynthPalette.mint)
        .preferredColorScheme(.light)
        .confirmationDialog("Create a new patch?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Create new patch", role: .destructive) { model.resetPatch() }
        } message: {
            Text("Export the current patch first if you want to keep it.")
        }
        .onDisappear { model.allNotesOff() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sound Dihsign")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SynthPalette.muted)
                TextField("Patch name", text: $model.patch.name)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .submitLabel(.done)
                    .accessibilityLabel("Patch name")
            }
            Spacer(minLength: 0)
            Button {
                if model.audioReady { model.stopAudio() } else { model.startAudio() }
            } label: {
                Image(systemName: model.audioReady ? "speaker.wave.2.fill" : "speaker.slash")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(model.audioReady ? SynthPalette.mint : SynthPalette.muted)
                    .frame(width: 44, height: 44)
                    .background(SynthPalette.panel, in: Circle())
            }
            .accessibilityLabel(model.audioReady ? "Stop audio" : "Start audio")
            Menu {
                Button("New patch", systemImage: "plus") { confirmingReset = true }
                Button("Import patch", systemImage: "square.and.arrow.down") { model.isImportingPatch = true }
                Button("Export patch", systemImage: "square.and.arrow.up") { model.isExportingPatch = true }
                Button("Release all notes", systemImage: "hand.raised") { model.allNotesOff() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(SynthPalette.panel, in: Circle())
            }
            .accessibilityLabel("Patch actions")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var pageTabs: some View {
        Picker("Sound controls", selection: $model.selectedPage) {
            ForEach(SynthPage.allCases, id: \.self) { page in
                Text(pageTitle(page)).tag(page)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .frame(minHeight: 44)
    }

    private var oscillatorPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Oscillator", selection: $model.selectedOscillator) {
                ForEach(0..<3, id: \.self) { index in
                    Text("Oscillator \(["A", "B", "C"][index])").tag(index)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            VStack(alignment: .leading, spacing: 16) {
                if oscillatorMode == 0 {
                    wavetableSelector
                    waveform
                } else {
                    samplePanel
                    if oscillatorMode == 3 && customWavetableLoaded { waveform }
                }
                generateButton
                octaveControls
                HStack(alignment: .top, spacing: 20) {
                    SynthParameter(model: model, id: oscillatorBase + 3, title: "Level")
                    SynthParameter(model: model, id: oscillatorBase + 2, title: positionTitle)
                }
            }
            .synthPanel()
            DisclosureGroup("Advanced", isExpanded: $showingAdvanced) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Oscillator mode").font(.subheadline.weight(.medium))
                        Picker("Oscillator mode", selection: Binding(get: { oscillatorMode }, set: { model.set(oscillatorBase, Float($0)) })) {
                            Text("Wave").tag(0)
                            Text("Sample").tag(1)
                            Text("Grain").tag(2)
                            Text("Spectral").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .frame(minHeight: 44)
                    }
                    parameterGrid(advancedOscillatorControls)
                    if oscillatorMode == 0 {
                        Button {
                            model.wavetableImportOscillator = model.selectedOscillator
                            model.isImportingWavetable = true
                        } label: {
                            Label("Import wavetable", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        Text("Mono WAV, 2,048 samples per frame, up to 256 frames.")
                            .font(.caption).foregroundStyle(SynthPalette.muted)
                    }
                    Divider()
                    Text("Layers").font(.subheadline.weight(.medium))
                    parameterGrid([.init(id: 138, title: "Sub"), .init(id: 139, title: "Noise")])
                }
                .padding(.top, 18)
            }
            .font(.subheadline.weight(.medium))
            .padding(.vertical, 8)
        }
    }

    private var waveform: some View {
        SynthWaveform(table: Int(model.value(oscillatorBase + 1)), position: model.value(oscillatorBase + 2), warp: model.value(oscillatorBase + 9), customTable: customWavetable)
            .frame(height: 104)
            .padding(.horizontal, 8)
            .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
            .accessibilityLabel("Wavetable shape preview")
    }

    private var wavetableSelector: some View {
        Menu {
            ForEach(Array(["Basic", "Growl", "Hollow"].enumerated()), id: \.offset) { index, title in
                Button { model.selectTable(index, oscillator: model.selectedOscillator) } label: {
                    if !customWavetableLoaded && Int(model.value(oscillatorBase + 1)) == index {
                        Label(title, systemImage: "checkmark")
                    } else { Text(title) }
                }
            }
            Divider()
            Button("Import wavetable", systemImage: "square.and.arrow.down") {
                model.wavetableImportOscillator = model.selectedOscillator
                model.isImportingWavetable = true
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tableTitle).font(.system(.headline, design: .rounded))
                    Text(customWavetableLoaded ? "Your wavetable" : "Wavetable")
                        .font(.caption).foregroundStyle(SynthPalette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold)).foregroundStyle(SynthPalette.muted)
            }
            .frame(minHeight: 44)
            .foregroundStyle(SynthPalette.text)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Choose wavetable. Current table: \(tableTitle)")
    }

    private var generateButton: some View {
        let generatingThisOscillator = model.generatingOscillator == model.selectedOscillator
        return Button {
            model.generateWavetable(for: model.selectedOscillator)
        } label: {
            HStack(spacing: 8) {
                if generatingThisOscillator {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(generatingThisOscillator ? "Generating…" : "Generate Wavetable")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .background(SynthPalette.mint, in: Capsule())
            .opacity(model.generatingOscillator != nil && !generatingThisOscillator ? 0.55 : 1)
        }
        .buttonStyle(FluidPressStyle())
        .disabled(model.generatingOscillator != nil)
        .accessibilityLabel(generatingThisOscillator ? "Generating wavetable" : "Generate a random wavetable for oscillator \(["A", "B", "C"][model.selectedOscillator])")
        .accessibilityHint("Creates a new playable wavetable and selects wavetable mode")
    }

    private var octaveControls: some View {
        let octave = Int(model.value(oscillatorBase + 13))
        return HStack(spacing: 12) {
            Text("Octave").font(.subheadline.weight(.medium))
            Spacer()
            Button { model.transposeOctave(for: model.selectedOscillator, by: -1) } label: {
                Image(systemName: "minus")
                    .font(.body.weight(.medium))
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
            }
            .buttonStyle(FluidPressStyle())
            .disabled(octave <= -4)
            .accessibilityLabel("Lower oscillator \(["A", "B", "C"][model.selectedOscillator]) one octave")
            VStack(spacing: 2) {
                Text(octave > 0 ? "+\(octave)" : "\(octave)")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
            .frame(minWidth: 42)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Oscillator tuning")
            .accessibilityValue("\(octave) octaves")
            Button { model.transposeOctave(for: model.selectedOscillator, by: 1) } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.medium))
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
            }
            .buttonStyle(FluidPressStyle())
            .disabled(octave >= 4)
            .accessibilityLabel("Raise oscillator \(["A", "B", "C"][model.selectedOscillator]) one octave")
        }
    }

    private var positionTitle: String {
        switch oscillatorMode {
        case 1: return "Start"
        case 3: return "Shape"
        default: return "Position"
        }
    }

    private var samplePanel: some View {
        let loaded = model.patch.samples.contains { $0.oscillator == model.selectedOscillator }
        let usingTable = oscillatorMode == 3 && customWavetableLoaded
        return VStack(alignment: .leading, spacing: 12) {
            Label(usingTable ? "Wavetable harmonics" : loaded ? "Audio loaded" : "Add a texture", systemImage: oscillatorMode == 2 ? "sparkles" : "waveform")
                .font(.headline)
            Text(usingTable ? "Explore your table as harmonics." : sampleExplanation)
                .font(.subheadline).foregroundStyle(SynthPalette.muted)
            Button {
                model.sampleImportOscillator = model.selectedOscillator
                model.isImportingSample = true
            } label: {
                Label(usingTable ? "Use audio instead" : loaded ? "Replace audio" : "Import audio", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
    }

    private var sampleExplanation: String {
        switch oscillatorMode {
        case 1: return "Play an audio one-shot across the keyboard."
        case 2: return "Explore your audio as overlapping grains."
        default: return "Explore the harmonics inside your audio."
        }
    }

    private var advancedOscillatorControls: [ParameterSpec] {
        let base = oscillatorBase
        var controls: [ParameterSpec] = [.init(id: base + 4, title: "Semitones"), .init(id: base + 5, title: "Fine tune"), .init(id: base + 8, title: "Pan"), .init(id: base + 9, title: "Warp"), .init(id: base + 6, title: "Unison"), .init(id: base + 7, title: "Detune")]
        if oscillatorMode == 2 {
            controls += [.init(id: base + 10, title: "Scan"), .init(id: base + 11, title: "Grain size"), .init(id: base + 12, title: "Density")]
        }
        return controls
    }

    private var filterPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Filter", subtitle: "Shape the space around your sound.")
            SynthFilterPlot(cutoff: model.value(128), resonance: model.value(129))
                .frame(height: 136)
                .accessibilityLabel("Low-pass response illustration")
            parameterGrid([.init(id: 128, title: "Cutoff"), .init(id: 129, title: "Resonance")])
        }
        .synthPanel()
    }

    private var envelopePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Envelope", subtitle: "Give every note its own shape.")
            SynthEnvelopePlot(attack: model.value(134), decay: model.value(135), sustain: model.value(136), release: model.value(137))
                .frame(height: 128)
                .accessibilityLabel("Attack, decay, sustain and release envelope")
            parameterGrid([.init(id: 134, title: "Attack"), .init(id: 135, title: "Decay"), .init(id: 136, title: "Sustain"), .init(id: 137, title: "Release")])
            Divider()
            sectionTitle("LFO 1", subtitle: "A gentle sine wave for movement.")
            SynthParameter(model: model, id: 132, title: "Rate")
        }
        .synthPanel()
    }

    private var effectsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            effectCard(title: "Drive", subtitle: "Add warmth and harmonic weight.", icon: "bolt", id: 130)
            effectCard(title: "Delay", subtitle: "Give your sound a little more space.", icon: "repeat", id: 131)
        }
    }

    private func effectCard(title: String, subtitle: String, icon: String, id: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon).font(.system(.title3, design: .rounded).weight(.semibold))
            Text(subtitle).font(.subheadline).foregroundStyle(SynthPalette.muted)
            SynthParameter(model: model, id: id, title: id == 130 ? "Amount" : "Mix")
        }
        .synthPanel()
    }

    private var modulationPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Modulation", subtitle: "Connect a source. Make it move.")
            modulationSources
            if model.patch.routes.isEmpty {
                Text("Drag a source onto any slider, or choose a source and tap the slider’s link button.")
                    .font(.subheadline).foregroundStyle(SynthPalette.muted)
                    .padding(.vertical, 12)
            } else {
                ForEach(model.patch.routes, id: \.slot) { route in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(sourceTitle(route.source)).font(.subheadline.weight(.medium))
                                Text(ParameterCatalog.name(route.destination)).font(.caption).foregroundStyle(SynthPalette.muted)
                            }
                            Spacer(minLength: 0)
                            Button { model.removeRoute(slot: route.slot) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(SynthPalette.muted)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Remove \(sourceTitle(route.source)) to \(ParameterCatalog.name(route.destination)) route")
                        }
                        HStack(spacing: 12) {
                            Slider(value: Binding(get: { route.amount }, set: { model.setRouteAmount(slot: route.slot, amount: $0) }), in: -1...1)
                                .frame(minHeight: 44)
                                .accessibilityLabel("\(sourceTitle(route.source)) to \(ParameterCatalog.name(route.destination)) depth")
                            Text(String(format: "%+.0f%%", route.amount * 100))
                                .font(.caption.monospacedDigit()).foregroundStyle(SynthPalette.muted)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    .synthPanel()
                }
            }
            SynthParameter(model: model, id: 140, title: "Macro 1").synthPanel()
        }
    }

    private var modulationSources: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(1...4, id: \.self) { source in
                    Button { model.selectedSource = source } label: {
                        Label(sourceTitle(source), systemImage: sourceIcon(source))
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(model.selectedSource == source ? .white : SynthPalette.mint)
                            .background(model.selectedSource == source ? SynthPalette.mint : SynthPalette.panel, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(FluidPressStyle())
                    .onDrag { NSItemProvider(object: "sounddihsign:source:\(source)" as NSString) }
                    .accessibilityAddTraits(model.selectedSource == source ? .isSelected : [])
                    .accessibilityHint("Select, then tap a slider’s link button")
                }
            }
            if model.selectedPage != .modulation {
                Button { model.selectedPage = .modulation } label: {
                    Label("Routes · \(model.patch.routes.count)", systemImage: "arrow.up.right")
                        .font(.subheadline)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private func keyboard(height: CGFloat) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Button {
                    model.allNotesOff()
                    model.octave = max(0, model.octave - 1)
                } label: {
                    Image(systemName: "minus").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Lower keyboard one octave")
                .disabled(model.octave <= 0)
                Text("C\(model.octave)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(SynthPalette.muted)
                    .frame(minWidth: 28)
                Button {
                    model.allNotesOff()
                    model.octave = min(7, model.octave + 1)
                } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Raise keyboard one octave")
                .disabled(model.octave >= 7)
                Spacer(minLength: 8)
                Image(systemName: "speaker.wave.2")
                    .font(.caption).foregroundStyle(SynthPalette.muted)
                    .accessibilityHidden(true)
                Slider(value: Binding(get: { model.value(133) }, set: { model.set(133, $0) }), in: 0...1)
                    .frame(maxWidth: 110, minHeight: 44)
                    .accessibilityLabel("Master volume")
                Button { model.allNotesOff() } label: {
                    Image(systemName: "hand.raised").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Release all notes")
            }
            .font(.system(size: 14, weight: .medium))
            TouchKeyboard(baseNote: (model.octave + 1) * 12, onNoteOn: { note, velocity in model.noteOn(note, velocity: velocity) }, onNoteOff: { model.noteOff($0) })
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(.white)
        .overlay(alignment: .top) { Rectangle().fill(SynthPalette.line.opacity(0.6)).frame(height: 0.5) }
    }

    private func parameterGrid(_ controls: [ParameterSpec]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 136), spacing: 20)], spacing: 16) {
            ForEach(controls) { spec in SynthParameter(model: model, id: spec.id, title: spec.title) }
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(.title2, design: .rounded).weight(.semibold))
            Text(subtitle).font(.subheadline).foregroundStyle(SynthPalette.muted)
        }
    }

    private func pageTitle(_ page: SynthPage) -> String {
        switch page {
        case .oscillator: return "Sound"
        case .filter: return "Filter"
        case .envelopes: return "Shape"
        case .effects: return "FX"
        case .modulation: return "Mod"
        }
    }
}

private struct ParameterSpec: Identifiable {
    let id: Int
    let title: String
}

/// Native sliders retain synth modulation and logarithmic response without visual clutter.
@MainActor
private struct SynthParameter: View {
    @ObservedObject var model: SynthModel
    let id: Int
    let title: String
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(title).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if !discrete {
                    Button { model.route(source: model.selectedSource, destination: id) } label: {
                        Image(systemName: hasRoute ? "link.circle.fill" : "link")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(hasRoute ? SynthPalette.mint : SynthPalette.muted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Link \(sourceTitle(model.selectedSource)) to \(ParameterCatalog.name(id))")
                } else {
                    Spacer().frame(height: 44)
                }
            }
            Slider(value: Binding(get: { normalized }, set: { applyNormalized($0) }), in: 0...1)
                .frame(minHeight: 44)
                .accessibilityLabel(ParameterCatalog.name(id))
                .accessibilityValue(displayValue)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: adjustAccessibility(up: true)
                    case .decrement: adjustAccessibility(up: false)
                    @unknown default: break
                    }
                }
            Text(displayValue)
                .font(.caption.monospacedDigit())
                .foregroundStyle(SynthPalette.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, dropTarget ? 6 : 0)
        .background(dropTarget ? SynthPalette.mint.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .onDrop(of: [UTType.plainText], isTargeted: $dropTarget) { providers in
            guard !discrete, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let token = object as? String, token.hasPrefix("sounddihsign:source:"),
                      let source = Int(token.split(separator: ":").last ?? ""), (1...4).contains(source) else { return }
                DispatchQueue.main.async { model.route(source: source, destination: id) }
            }
            return true
        }
        .contextMenu {
            if !discrete {
                Button("Link \(sourceTitle(model.selectedSource))", systemImage: "link") { model.route(source: model.selectedSource, destination: id) }
            }
            Button("Reset \(title)", systemImage: "arrow.counterclockwise") {
                if let descriptor = ParameterCatalog.descriptor(id) { model.set(id, descriptor.defaultValue) }
            }
        }
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
            case 4: return String(format: "%+.1f st", value)
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

private struct FluidPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
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
        padding(18)
            .background(SynthPalette.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
