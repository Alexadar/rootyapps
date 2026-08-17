import SwiftUI
import WatchKit
import TimingKit
import PitchKit
import SPLKit
import SabineKit
import AudioUtilKit
import PartchKit
import CommaKit
import MersenneKit
import WebsterKit
import BernoulliKit
import FormantKit
import RoomModesKit
import AirAbsorptionKit
import InterferenceKit
import ButterworthKit
import FletcherKit
import PassiveKit
import BiquadKit
import DynamicsKit
import StereoKit
import ThieleKit

// MARK: - Paging model

/// One page per tool, plus the catalog at index 0.
///
/// Two states, one at a time: the catalog, or one tool.
///
/// There is no paging between tools. It was tried on the wrist and lost twice over — reaching the
/// catalog from the 20th tool was twenty swipes, and vertical paging fought the Digital Crown for
/// every turn, so a crown twist meant to change a value would leave the screen instead. Removing
/// it hands the crown back to the fields, which is the only thing it should ever have driven here.
enum WatchPage: Hashable {
    case list
    case tool(Tool)
}

// MARK: - Front door

/// Opens on the last-used tool, already showing a number: zero taps to an answer.
/// Back to the catalog is a left-to-right swipe or a tap on the header.
struct WatchRootView: View {
    @AppStorage("otl.watch.lastTool") private var lastToolID: String = Tool.tempo.rawValue
    @State private var page: WatchPage = .list

    var body: some View {
        ZStack {
            OTL.background.ignoresSafeArea()
            switch page {
            case .list:
                WatchToolList(selection: $page)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .tool(let tool):
                WatchToolView(tool: tool, page: $page)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onAppear {
            // Land on the tool the wrist was last using, not on the catalog: the whole point of
            // this app is that the answer is already on screen when it lights up.
            if let last = Tool(rawValue: lastToolID) { page = .tool(last) }
        }
        .onChange(of: page) { _, new in
            if case .tool(let t) = new { lastToolID = t.rawValue }
        }
    }
}

// MARK: - Tool screen

struct WatchToolView: View {
    let tool: Tool
    @Binding var page: WatchPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // The header IS the way back to the catalog. Paging down works too, but from the
                // 20th tool that is twenty swipes — the list has to be one tap from anywhere.
                Button { page = .list } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tool.symbol).foregroundStyle(tool.accent)
                        Text(tool.title)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(OTL.textSecondary)
                        Spacer(minLength: 2)
                        // Twice the glyph it started as, on its own tinted disc: at a glance this
                        // has to read as the way out, not as decoration next to the title.
                        Image(systemName: "list.bullet")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(tool.accent)
                            .frame(width: 34, height: 34)
                            .background(tool.accent.opacity(0.16), in: .circle)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .focusable(false)          // same reason: it must never hold the crown's focus
                .accessibilityIdentifier("nav.toolList")
                .accessibilityLabel(Text("All tools"))
                body(for: tool)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .background(
            RadialGradient(colors: [tool.accent.opacity(0.18), .clear],
                           center: .top, startRadius: 0, endRadius: 170)
                .ignoresSafeArea()
        )
        // Swipe left-to-right → the catalog: the same direction watchOS uses for "back" everywhere
        // else, so the hand already knows it. The header button stays as the visible affordance.
        // simultaneousGesture, not gesture, so the screen still scrolls; the 2:1 test keeps a
        // diagonal scroll from being read as a sideways flick.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { drag in
                    guard drag.translation.width > 40,
                          abs(drag.translation.width) > abs(drag.translation.height) * 2 else { return }
                    WKInterfaceDevice.current().play(.click)
                    withAnimation { page = .list }
                }
        )
    }

    // Split in two: a single 26-case switch in one `body` blows past the type-checker's
    // expression limit and the compiler reports it as an unrelated error miles away.
    @ViewBuilder private func body(for tool: Tool) -> some View {
        switch tool.section {
        case .timing, .tuning, .design: firstHalf(tool)
        default: secondHalf(tool)
        }
    }

    @ViewBuilder private func firstHalf(_ tool: Tool) -> some View {
        let a = tool.accent
        switch tool {
        case .tempo:    TempoWatch(accent: a)
        case .delay:    DelayWatch(accent: a)
        case .timecode: TimecodeWatch(accent: a)
        case .pitch:    PitchWatch(accent: a)
        case .partch:   PartchWatch(accent: a)
        case .comma:    CommaWatch(accent: a)
        case .mersenne: MersenneWatch(accent: a)
        case .thiele:   ThieleWatch(accent: a)
        default:        EmptyView()
        }
    }

    @ViewBuilder private func secondHalf(_ tool: Tool) -> some View {
        let a = tool.accent
        switch tool {
        case .sabine:      SabineWatch(accent: a)
        case .webster:     WebsterWatch(accent: a)
        case .bernoulli:   BernoulliWatch(accent: a)
        case .formant:     FormantWatch(accent: a)
        case .spl:         SPLWatch(accent: a)
        case .roommodes:   RoomModesWatch(accent: a)
        case .air:         AirWatch(accent: a)
        case .sbir:        SBIRWatch(accent: a)
        case .butterworth: ButterworthWatch(accent: a)
        case .fletcher:    FletcherWatch(accent: a)
        case .benchmark:   BenchmarkWatch(accent: a)
        case .passive:     PassiveWatch(accent: a)
        case .biquad:      BiquadWatch(accent: a)
        case .compressor:  CompressorWatch(accent: a)
        case .sra:         SRAWatch(accent: a)
        case .levels:      LevelsWatch(accent: a)
        case .file:        FileWatch(accent: a)
        case .pan:         PanWatch(accent: a)
        default:           EmptyView()
        }
    }
}

/// Every screen below is the tool's *primary* sub-screen only. Reference tables and the second
/// and third sub-screens stay on phone and Mac — a wrist is for the one number you need mid-take,
/// and inputs beyond the two most consequential ones sit at the phone's own defaults so the two
/// devices agree when you check them side by side.

// MARK: - Timing

/// Tempo — the one screen where the wrist beats the phone: tap the tempo instead of typing it.
private struct TempoWatch: View {
    let accent: Color
    @EnvironmentObject private var crownFocus: CrownFocus
    @ObservedObject private var transport = SessionTransport.shared
    @StateObject private var tap = TapTempo()
    @State private var bpm: Double = 120
    /// Non-nil while this screen is still showing the phone's measurement. Cleared by the first crown
    /// detent and by tap tempo — both are the user saying the number is theirs now.
    @State private var measuredFrom: String?

    private var ms: Double { Tempo.noteMs(bpm: bpm, division: 4) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Note length", value: Fmt.f(ms, 1), unit: "ms",
                           accent: accent, hero: true, id: "result.tempo")
            StackedReadout(label: "One bar", value: Fmt.f(Tempo.barMs(bpm: bpm, beats: 4, beatUnit: 4), 0), unit: "ms")
            CrownField(label: "Tempo", value: $bpm, unit: "BPM",
                       step: 1, range: 30...300, targeted: true, accent: accent,
                       measuredSource: measuredFrom)
            Button {
                tap.tap()
                bpm = tap.bpm
                measuredFrom = nil          // a tapped tempo is not a measured one
                // This button is the whole point of the screen, and tapping it takes the crown's
                // focus. Without this the tempo field goes dead the moment you tap a tempo.
                crownFocus.reclaim()
            } label: {
                Label("Tap tempo", systemImage: "hand.tap")
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(accent)
            // The actual cure, not just first aid: a Button is focusable by default, so tapping this
            // one MOVED focus off the tempo field and the crown went dead. Handing focus back after
            // the fact does not work — the tap's own focus change lands after the action runs, and
            // overwrites it. Refusing focus here means it is never taken.
            .focusable(false)
            .accessibilityIdentifier("input.tapTempo")
        }
        // Receive, never capture: the wrist shows what the phone measured, marked the same way.
        .onAppear { adoptMeasurement() }
        .onChange(of: transport.received) { _, _ in adoptMeasurement() }
        // THE FIRST CROWN DETENT OVERRIDES. Turning the crown is the user taking the value over, so
        // the marking goes at once — no "measured but modified" on the wrist either.
        .onChange(of: bpm) { _, new in
            guard measuredFrom != nil else { return }
            if let measured = transport.received?.bpm, abs(measured - new) < 0.001 { return }
            measuredFrom = nil
        }
    }

    private func adoptMeasurement() {
        guard let session = transport.received, let measured = session.bpm else { return }
        bpm = measured
        measuredFrom = session.sourceName
    }
}

private struct DelayWatch: View {
    let accent: Color
    @State private var bpm: Double = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Delay time", value: Fmt.f(Delay.noteDelayMs(bpm: bpm, division: 4), 1),
                           unit: "ms", accent: accent, hero: true, id: "result.delay")
            StackedReadout(label: "Rate", value: Fmt.f(Delay.rateHz(ms: Delay.noteDelayMs(bpm: bpm, division: 4)), 2), unit: "Hz")
            CrownField(label: "Tempo", value: $bpm, unit: "BPM",
                       step: 1, range: 30...300, targeted: true, accent: accent)
        }
    }
}

private struct TimecodeWatch: View {
    let accent: Color
    @State private var frames: Double = 108_000     // 1 h at 30 fps
    @State private var fps: Double = 30

    private var label: String {
        SMPTE.timecode(frameCount: Int(frames), fps: Int(fps), dropFrame: false).label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Timecode", value: label, accent: accent, hero: true, id: "result.timecode")
            StackedReadout(label: "Duration", value: Fmt.f(frames / max(fps, 1), 2), unit: "s")
            CrownField(label: "Frame count", value: $frames, unit: "",
                       step: 1, range: 0...900_000, targeted: true, accent: accent)
            CrownField(label: "Frame rate", value: $fps, unit: "fps",
                       step: 1, range: 23...60, targeted: false, accent: accent)
        }
    }
}

private struct PitchWatch: View {
    let accent: Color
    @State private var midi: Double = 69          // A4

    private var hz: Double { Pitch.noteToHz(midi: midi) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Frequency", value: Fmt.f(hz, 2), unit: "Hz", accent: accent, hero: true, id: "result.pitch")
            StackedReadout(label: "Wavelength", value: Fmt.f(Pitch.wavelengthM(hz: hz), 3), unit: "m")
            // Snaps chromatic — the crown must never land between two notes.
            CrownField(label: "Note", value: $midi, unit: Pitch.noteName(midi: Int(midi.rounded())),
                       step: 1, range: 21...108, targeted: true, accent: accent)
        }
    }
}

// MARK: - Tuning

private struct PartchWatch: View {
    let accent: Color
    @State private var low: Double = 220
    @State private var high: Double = 330
    @State private var target = 0

    private var cents: Double { Spectral.cents(high / max(low, 0.0001)) }
    private var just: (num: Int, den: Int, cents: Double) {
        Spectral.nearestJustRatio(cents: cents, oddLimit: 15)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Interval", value: Fmt.f(cents, 1), unit: "¢", accent: accent, hero: true, id: "result.partch")
            StackedReadout(label: "Nearest just", value: "\(just.num):\(just.den)",
                           unit: Fmt.signed(cents - just.cents, 1) + " ¢")
            CrownField(label: "Lower", value: $low, unit: "Hz",
                       step: 1, range: 20...4000, targeted: target == 0, accent: accent)
                .onTapGesture { target = 0 }
            CrownField(label: "Upper", value: $high, unit: "Hz",
                       step: 1, range: 20...4000, targeted: target == 1, accent: accent)
                .onTapGesture { target = 1 }
        }
    }
}

private struct CommaWatch: View {
    let accent: Color
    @State private var edo: Double = 12

    private var step: Double { 1200 / max(edo, 1) }
    /// How far this EDO's best fifth misses just — the number that decides whether a temperament
    /// is usable, and the reason anyone opens this tool away from a desk.
    private var fifthError: Double {
        let k = (Tuning.justFifthCents / step).rounded()
        return k * step - Tuning.justFifthCents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Step size", value: Fmt.f(step, 2), unit: "¢", accent: accent, hero: true, id: "result.comma")
            StackedReadout(label: "Best fifth error", value: Fmt.signed(fifthError, 2), unit: "¢")
            CrownField(label: "Divisions per octave", value: $edo, unit: "EDO",
                       step: 1, range: 5...72, targeted: true, accent: accent)
        }
    }
}

private struct MersenneWatch: View {
    let accent: Color
    @State private var freq: Double = 110
    @State private var length: Double = 0.65
    @State private var target = 0

    private var newtons: Double {
        Strings.tensionN(frequencyHz: freq, lengthM: max(length, 0.01), linearDensityKgPerM: 0.005)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Tension", value: Fmt.f(newtons, 1), unit: "N", accent: accent, hero: true, id: "result.mersenne")
            StackedReadout(label: "Tension", value: Fmt.f(newtons / 4.4482216, 1), unit: "lbf")
            CrownField(label: "Frequency", value: $freq, unit: "Hz",
                       step: 1, range: 20...1000, targeted: target == 0, accent: accent)
                .onTapGesture { target = 0 }
            CrownField(label: "Scale length", value: $length, unit: "m",
                       step: 0.01, range: 0.2...2, targeted: target == 1, accent: accent, fraction: 2)
                .onTapGesture { target = 1 }
        }
    }
}

// MARK: - Acoustics

private struct SabineWatch: View {
    let accent: Color
    @State private var volume: Double = 200
    @State private var absorption: Double = 40
    @State private var target = 0

    private var rt60: Double { Acoustics.sabineRT60(volumeM3: volume, absorptionSabins: max(absorption, 0.01)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "RT60 (Sabine)", value: Fmt.f(rt60, 2), unit: "s", accent: accent, hero: true, id: "result.sabine")
            StackedReadout(label: "Schroeder freq",
                           value: Fmt.f(Acoustics.schroederHz(rt60: rt60, volumeM3: volume), 0), unit: "Hz")
            // 5 m³ detent: rooms are estimated, and a finer step would imply false precision.
            CrownField(label: "Volume", value: $volume, unit: "m³",
                       step: 5, range: 10...2000, targeted: target == 0, accent: accent)
                .onTapGesture { target = 0 }
            CrownField(label: "Absorption ΣSα", value: $absorption, unit: "sabins",
                       step: 1, range: 1...500, targeted: target == 1, accent: accent)
                .onTapGesture { target = 1 }
        }
    }
}

private struct WebsterWatch: View {
    let accent: Color
    @State private var throatCm: Double = 2.5
    @State private var mouthCm: Double = 40
    @State private var target = 0

    private func area(_ diaCm: Double) -> Double { .pi * pow(diaCm / 100 / 2, 2) }
    private var flare: Double {
        let t = area(throatCm), m = area(mouthCm)
        guard t > 0, m > 0 else { return 0 }
        return log(m / t) / 0.6                       // 60 cm horn, the phone's default length
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Cutoff", value: Fmt.f(Horns.expHornCutoffHz(flareConstant: flare), 1),
                           unit: "Hz", accent: accent, hero: true, id: "result.webster")
            StackedReadout(label: "Flare constant", value: Fmt.f(flare, 2), unit: "1/m")
            CrownField(label: "Throat diameter", value: $throatCm, unit: "cm",
                       step: 0.5, range: 1...20, targeted: target == 0, accent: accent, fraction: 1)
                .onTapGesture { target = 0 }
            CrownField(label: "Mouth diameter", value: $mouthCm, unit: "cm",
                       step: 1, range: 5...200, targeted: target == 1, accent: accent)
                .onTapGesture { target = 1 }
        }
    }
}

private struct BernoulliWatch: View {
    let accent: Color
    @EnvironmentObject private var crownFocus: CrownFocus
    @State private var length: Double = 0.5
    @State private var isOpen = true

    private var hz: Double {
        isOpen ? Pipes.openPipeHz(lengthM: max(length, 0.01), harmonic: 1)
               : Pipes.closedPipeHz(lengthM: max(length, 0.01), harmonic: 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Fundamental", value: Fmt.f(hz, 1), unit: "Hz", accent: accent, hero: true, id: "result.bernoulli")
            StackedReadout(label: "Second harmonic",
                           value: Fmt.f(isOpen ? Pipes.openPipeHz(lengthM: max(length, 0.01), harmonic: 2)
                                               : Pipes.closedPipeHz(lengthM: max(length, 0.01), harmonic: 3), 1),
                           unit: "Hz")
            CrownField(label: "Length", value: $length, unit: "m",
                       step: 0.01, range: 0.05...5, targeted: true, accent: accent, fraction: 2)
            Toggle(isOn: $isOpen) {
                Text("Open both ends")
                    .font(.system(.caption2, design: .monospaced))
            }
            .tint(accent)
            .onChange(of: isOpen) { _, _ in crownFocus.reclaim() }   // a Toggle takes focus too
        }
    }
}

private struct FormantWatch: View {
    let accent: Color
    @State private var tractCm: Double = 17.5

    private func formant(_ n: Int) -> Double {
        Formants.formantHz(tractLengthM: max(tractCm, 1) / 100, n: n)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "F1", value: Fmt.f(formant(1), 0), unit: "Hz", accent: accent, hero: true, id: "result.formant")
            StackedReadout(label: "F2", value: Fmt.f(formant(2), 0), unit: "Hz")
            CrownField(label: "Tract length", value: $tractCm, unit: "cm",
                       step: 0.5, range: 8...25, targeted: true, accent: accent, fraction: 1)
        }
    }
}

private struct SPLWatch: View {
    let accent: Color
    @State private var spl: Double = 100
    @State private var distance: Double = 4
    @State private var target = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "SPL at new distance",
                           value: Fmt.f(SPL.atDistance(spl1: spl, from: 1, to: max(distance, 0.1)), 1),
                           unit: "dB", accent: accent, hero: true, id: "result.spl")
            CrownField(label: "SPL at reference", value: $spl, unit: "dB",
                       step: 0.5, range: 40...140, targeted: target == 0, accent: accent, fraction: 1)
                .onTapGesture { target = 0 }
            CrownField(label: "New distance", value: $distance, unit: "m",
                       step: 0.5, range: 0.5...100, targeted: target == 1, accent: accent, fraction: 1)
                .onTapGesture { target = 1 }
        }
    }
}

private struct RoomModesWatch: View {
    let accent: Color
    @State private var length: Double = 5
    @State private var width: Double = 4
    @State private var target = 0

    private var modes: [RoomModes.Mode] {
        RoomModes.modes(lengthM: max(length, 1), widthM: max(width, 1), heightM: 2.8,
                        speed: 343, maxHz: 300)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Lowest mode", value: Fmt.f(modes.first?.hz ?? 0, 1),
                           unit: "Hz", accent: accent, hero: true, id: "result.roommodes")
            StackedReadout(label: "Modes below 300 Hz", value: Fmt.count(Double(modes.count)))
            // Height stays at the phone's 2.8 m default: two dimensions fit the wrist, three do not.
            CrownField(label: "Length", value: $length, unit: "m",
                       step: 0.1, range: 2...20, targeted: target == 0, accent: accent, fraction: 1)
                .onTapGesture { target = 0 }
            CrownField(label: "Width", value: $width, unit: "m",
                       step: 0.1, range: 2...20, targeted: target == 1, accent: accent, fraction: 1)
                .onTapGesture { target = 1 }
        }
    }
}

private struct AirWatch: View {
    let accent: Color
    @State private var freq: Double = 4000
    @State private var distance: Double = 100
    @State private var target = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Loss over distance",
                           value: Fmt.f(Atmosphere.lossDB(freqHz: freq, tempC: 20, humidityPct: 50,
                                                          distanceM: distance, pressureKPa: 101.325), 2),
                           unit: "dB", accent: accent, hero: true, id: "result.air")
            StackedReadout(label: "Absorption",
                           value: Fmt.f(Atmosphere.absorptionDBPerKm(freqHz: freq, tempC: 20,
                                                                     humidityPct: 50, pressureKPa: 101.325), 2),
                           unit: "dB/km")
            CrownField(label: "Frequency", value: $freq, unit: "Hz",
                       step: 100, range: 100...20000, targeted: target == 0, accent: accent)
                .onTapGesture { target = 0 }
            CrownField(label: "Distance", value: $distance, unit: "m",
                       step: 5, range: 5...1000, targeted: target == 1, accent: accent)
                .onTapGesture { target = 1 }
        }
    }
}

private struct SBIRWatch: View {
    let accent: Color
    @State private var distance: Double = 0.6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "First notch",
                           value: Fmt.f(Comb.boundaryNotches(distanceM: max(distance, 0.05), count: 1).first ?? 0, 1),
                           unit: "Hz", accent: accent, hero: true, id: "result.sbir")
            StackedReadout(label: "First peak",
                           value: Fmt.f(Comb.boundaryFirstPeak(distanceM: max(distance, 0.05)), 1), unit: "Hz")
            CrownField(label: "Distance to boundary", value: $distance, unit: "m",
                       step: 0.05, range: 0.05...5, targeted: true, accent: accent, fraction: 2)
        }
    }
}

// MARK: - Signal

private struct ButterworthWatch: View {
    let accent: Color
    @State private var fc: Double = 1000
    @State private var test: Double = 2000
    @State private var target = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Response",
                           value: Fmt.f(Filters.butterworthDB(order: 4, ratio: test / max(fc, 0.0001)), 2),
                           unit: "dB", accent: accent, hero: true, id: "result.butterworth")
            StackedReadout(label: "Slope (4th order)", value: "24", unit: "dB/oct")
            CrownField(label: "Cutoff", value: $fc, unit: "Hz",
                       step: 10, range: 20...20000, targeted: target == 0, accent: accent)
                .onTapGesture { target = 0 }
            CrownField(label: "Test frequency", value: $test, unit: "Hz",
                       step: 10, range: 20...20000, targeted: target == 1, accent: accent)
                .onTapGesture { target = 1 }
        }
    }
}

private struct FletcherWatch: View {
    let accent: Color
    @State private var freq: Double = 1000

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "A-weighting", value: Fmt.signed(Weighting.aWeightingDB(freq), 2),
                           unit: "dB", accent: accent, hero: true, id: "result.fletcher")
            StackedReadout(label: "C-weighting", value: Fmt.signed(Weighting.cWeightingDB(freq), 2), unit: "dB")
            CrownField(label: "Frequency", value: $freq, unit: "Hz",
                       step: 10, range: 10...20000, targeted: true, accent: accent)
        }
    }
}

private struct BenchmarkWatch: View {
    let accent: Color
    @State private var measured: Double = -9
    @State private var streamTarget: Double = -14      // Spotify / Apple Music
    @State private var target = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Gain to target", value: Fmt.signed(streamTarget - measured, 1),
                           unit: "dB", accent: accent, hero: true, id: "result.benchmark")
            CrownField(label: "Measured", value: $measured, unit: "LUFS",
                       step: 0.1, range: -40...0, targeted: target == 0, accent: accent, fraction: 1)
                .onTapGesture { target = 0 }
            CrownField(label: "Target", value: $streamTarget, unit: "LUFS",
                       step: 0.5, range: -30...0, targeted: target == 1, accent: accent, fraction: 1)
                .onTapGesture { target = 1 }
        }
    }
}

private struct PassiveWatch: View {
    let accent: Color
    @State private var kOhms: Double = 1
    @State private var microFarads: Double = 1
    @State private var target = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "RC cutoff",
                           value: Fmt.f(Passive.rcCutoffHz(resistanceOhms: max(kOhms, 0.001) * 1000,
                                                           capacitanceFarads: max(microFarads, 0.001) * 1e-6), 1),
                           unit: "Hz", accent: accent, hero: true, id: "result.passive")
            CrownField(label: "Resistance", value: $kOhms, unit: "kΩ",
                       step: 0.1, range: 0.1...1000, targeted: target == 0, accent: accent, fraction: 1)
                .onTapGesture { target = 0 }
            CrownField(label: "Capacitance", value: $microFarads, unit: "µF",
                       step: 0.01, range: 0.01...100, targeted: target == 1, accent: accent, fraction: 2)
                .onTapGesture { target = 1 }
        }
    }
}

private struct BiquadWatch: View {
    let accent: Color
    @State private var f0: Double = 1000
    @State private var q: Double = 0.7071
    @State private var target = 0

    private var coeffs: Biquad.Coeffs {
        Biquad.design(.lowpass, fs: 48000, f0: max(f0, 10), q: max(q, 0.1), gainDB: 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Level at cutoff",
                           value: Fmt.signed(Biquad.magnitudeDB(coeffs, hz: max(f0, 10), fs: 48000), 2),
                           unit: "dB", accent: accent, hero: true, id: "result.biquad")
            StackedReadout(label: "One octave up",
                           value: Fmt.signed(Biquad.magnitudeDB(coeffs, hz: max(f0, 10) * 2, fs: 48000), 2),
                           unit: "dB")
            // Lowpass at 48 kHz — the phone is where you pick a kind and a sample rate.
            CrownField(label: "Cutoff", value: $f0, unit: "Hz",
                       step: 10, range: 20...20000, targeted: target == 0, accent: accent)
                .onTapGesture { target = 0 }
            CrownField(label: "Q", value: $q, unit: "",
                       step: 0.05, range: 0.1...10, targeted: target == 1, accent: accent, fraction: 3)
                .onTapGesture { target = 1 }
        }
    }
}

private struct CompressorWatch: View {
    let accent: Color
    @State private var input: Double = -10
    @State private var threshold: Double = -20
    @State private var target = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Gain reduction",
                           value: Fmt.f(Compressor.gainReductionDB(inputDB: input, thresholdDB: threshold,
                                                                   ratio: 4, kneeDB: 6), 2),
                           unit: "dB", accent: accent, hero: true, id: "result.compressor")
            StackedReadout(label: "Output",
                           value: Fmt.signed(Compressor.outputLevelDB(inputDB: input, thresholdDB: threshold,
                                                                      ratio: 4, kneeDB: 6, makeupDB: 0), 2),
                           unit: "dB")
            // 4:1 with a 6 dB knee — the phone's defaults, so both devices agree at a glance.
            CrownField(label: "Input", value: $input, unit: "dB",
                       step: 0.5, range: -60...10, targeted: target == 0, accent: accent, fraction: 1)
                .onTapGesture { target = 0 }
            CrownField(label: "Threshold", value: $threshold, unit: "dB",
                       step: 0.5, range: -60...0, targeted: target == 1, accent: accent, fraction: 1)
                .onTapGesture { target = 1 }
        }
    }
}

// MARK: - Stereo

private struct SRAWatch: View {
    let accent: Color
    @State private var micAngle: Double = 110
    @State private var spacing: Double = 17
    @State private var target = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Recording angle",
                           value: Fmt.f(Stereo.recordingAngleDeg(micAngleDeg: micAngle, spacingCm: spacing,
                                                                 pattern: .cardioid, speed: 343), 1),
                           unit: "°", accent: accent, hero: true, id: "result.sra")
            StackedReadout(label: "Time difference at 45°",
                           value: Fmt.f(Stereo.timeDifferenceUs(sourceDeg: 45, spacingCm: spacing, speed: 343), 1),
                           unit: "µs")
            CrownField(label: "Microphone angle", value: $micAngle, unit: "°",
                       step: 1, range: 0...180, targeted: target == 0, accent: accent)
                .onTapGesture { target = 0 }
            CrownField(label: "Spacing", value: $spacing, unit: "cm",
                       step: 0.5, range: 0...60, targeted: target == 1, accent: accent, fraction: 1)
                .onTapGesture { target = 1 }
        }
    }
}

// MARK: - Utility

private struct LevelsWatch: View {
    let accent: Color
    @State private var db: Double = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Voltage ratio", value: Fmt.f(Levels.voltageRatio(db: db), 3),
                           unit: "×", accent: accent, hero: true, id: "result.levels")
            StackedReadout(label: "Power ratio", value: Fmt.f(Levels.powerRatio(db: db), 3), unit: "×")
            CrownField(label: "Level", value: $db, unit: "dB",
                       step: 0.5, range: -60...60, targeted: true, accent: accent, fraction: 1)
        }
    }
}

private struct FileWatch: View {
    let accent: Color
    @State private var minutes: Double = 3
    @State private var bits: Double = 24
    @State private var target = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "File size",
                           value: Fmt.f(FileInfo.sizeMB(sampleRate: 48000, bitDepth: bits,
                                                        channels: 2, seconds: minutes * 60), 1),
                           unit: "MB", accent: accent, hero: true, id: "result.file")
            StackedReadout(label: "Dynamic range",
                           value: Fmt.f(FileInfo.dynamicRangeDB(bitDepth: bits), 1), unit: "dB")
            // 48 kHz stereo — the common case; the phone covers the rest.
            CrownField(label: "Duration", value: $minutes, unit: "min",
                       step: 0.5, range: 0.5...600, targeted: target == 0, accent: accent, fraction: 1)
                .onTapGesture { target = 0 }
            // 8-bit detent so the crown can only land on 8, 16, 24 or 32.
            CrownField(label: "Bit depth", value: $bits, unit: "bit",
                       step: 8, range: 8...32, targeted: target == 1, accent: accent)
                .onTapGesture { target = 1 }
        }
    }
}

private struct PanWatch: View {
    let accent: Color
    @State private var position: Double = 0        // −1 … +1

    private var g: (left: Double, right: Double) { Pan.gains(position: position) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Left gain", value: Fmt.f(Levels.voltageDB(ratio: max(g.left, 1e-6)), 1),
                           unit: "dB", accent: accent, hero: true, id: "result.pan")
            StackedReadout(label: "Right gain", value: Fmt.f(Levels.voltageDB(ratio: max(g.right, 1e-6)), 1), unit: "dB")
            CrownField(label: "Pan", value: $position, unit: "",
                       step: 0.05, range: -1...1, targeted: true, accent: accent, fraction: 2)
        }
    }
}

// MARK: - Design

private struct ThieleWatch: View {
    let accent: Color
    @State private var vb: Double = 50
    @State private var qts: Double = 0.4
    @State private var target = 0

    private var driver: Driver { Driver(fsHz: 25, qts: max(qts, 0.05), vasLiters: 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Qtc (sealed)", value: Fmt.f(Sealed.qtc(driver, vbLiters: max(vb, 1)), 3),
                           accent: accent, hero: true, id: "result.thiele")
            StackedReadout(label: "F3", value: Fmt.f(Sealed.f3Hz(driver, vbLiters: max(vb, 1)), 1), unit: "Hz")
            // fs 25 Hz, Vas 100 L — the phone's default driver; change those there.
            CrownField(label: "Box volume", value: $vb, unit: "L",
                       step: 1, range: 2...500, targeted: target == 0, accent: accent)
                .onTapGesture { target = 0 }
            CrownField(label: "Qts", value: $qts, unit: "",
                       step: 0.01, range: 0.1...1.2, targeted: target == 1, accent: accent, fraction: 2)
                .onTapGesture { target = 1 }
        }
    }
}
