import SwiftUI
import TimingKit
import PitchKit
import SPLKit
import SabineKit
import AudioUtilKit

// MARK: - Curation

extension Tool {
    /// The only tools that ship on watchOS: one or two inputs, one number out.
    /// The other 19 stay on phone and Mac — Thiele and Biquad need too many inputs, Room Modes
    /// and Formant answer with a list, and Timecode and File are slower here than on a keyboard.
    /// See DESIGN_GUIDELINES §8.
    static let watchTools: [Tool] = [.tempo, .delay, .pitch, .spl, .sabine, .levels, .pan]
}

// MARK: - Front door — "Straight In"

/// Opens on the last-used tool, already showing a number: zero taps to an answer.
/// Crown-page or swipe between the seven. A bounded list of seven is what makes this safe;
/// over 26 it would be a maze.
struct WatchRootView: View {
    @AppStorage("otl.watch.lastTool") private var lastToolID: String = Tool.tempo.rawValue

    private var selection: Binding<Tool> {
        Binding(get: { Tool(rawValue: lastToolID).flatMap { Tool.watchTools.contains($0) ? $0 : nil } ?? .tempo },
                set: { lastToolID = $0.rawValue })
    }

    var body: some View {
        TabView(selection: selection) {
            ForEach(Tool.watchTools) { tool in
                WatchToolView(tool: tool).tag(tool)
            }
        }
        .tabViewStyle(.verticalPage)          // page dots teach the seven on first run
        .background(OTL.background)
    }
}

// MARK: - Tool screen

struct WatchToolView: View {
    let tool: Tool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: tool.symbol).foregroundStyle(tool.accent)
                    Text(tool.title)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(OTL.textSecondary)
                }
                switch tool {
                case .tempo:  TempoWatch(accent: tool.accent)
                case .delay:  DelayWatch(accent: tool.accent)
                case .pitch:  PitchWatch(accent: tool.accent)
                case .spl:    SPLWatch(accent: tool.accent)
                case .sabine: SabineWatch(accent: tool.accent)
                case .levels: LevelsWatch(accent: tool.accent)
                case .pan:    PanWatch(accent: tool.accent)
                default:      EmptyView()
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .containerBackground(tool.accent.gradient.opacity(0.18), for: .tabView)
    }
}

// MARK: - The seven

/// Tempo — the one screen where the wrist beats the phone: tap the tempo instead of typing it.
private struct TempoWatch: View {
    let accent: Color
    @StateObject private var tap = TapTempo()
    @State private var bpm: Double = 120
    @State private var targeted = true

    private var ms: Double { Tempo.noteMs(bpm: bpm, division: 4) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Note length", value: Fmt.f(ms, 1), unit: "ms",
                           accent: accent, hero: true)
            StackedReadout(label: "One bar", value: Fmt.f(Tempo.barMs(bpm: bpm, beats: 4, beatUnit: 4), 0), unit: "ms")
            CrownField(label: "Tempo", value: $bpm, unit: "BPM",
                       step: 1, range: 30...300, targeted: targeted, accent: accent)
            Button {
                tap.tap()
                bpm = tap.bpm
            } label: {
                Label("Tap tempo", systemImage: "hand.tap")
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(accent)
        }
    }
}

private struct DelayWatch: View {
    let accent: Color
    @State private var bpm: Double = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Delay time", value: Fmt.f(Delay.noteDelayMs(bpm: bpm, division: 4), 1),
                           unit: "ms", accent: accent, hero: true)
            StackedReadout(label: "Rate", value: Fmt.f(Delay.rateHz(ms: Delay.noteDelayMs(bpm: bpm, division: 4)), 2), unit: "Hz")
            CrownField(label: "Tempo", value: $bpm, unit: "BPM",
                       step: 1, range: 30...300, targeted: true, accent: accent)
        }
    }
}

private struct PitchWatch: View {
    let accent: Color
    @State private var midi: Double = 69          // A4

    private var hz: Double { Pitch.noteToHz(midi: midi) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Frequency", value: Fmt.f(hz, 2), unit: "Hz", accent: accent, hero: true)
            StackedReadout(label: "Wavelength", value: Fmt.f(Pitch.wavelengthM(hz: hz), 3), unit: "m")
            // Snaps chromatic — the crown must never land between two notes.
            CrownField(label: "Note", value: $midi, unit: Pitch.noteName(midi: Int(midi.rounded())),
                       step: 1, range: 21...108, targeted: true, accent: accent)
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
                           unit: "dB", accent: accent, hero: true)
            CrownField(label: "SPL at reference", value: $spl, unit: "dB",
                       step: 0.5, range: 40...140, targeted: target == 0, accent: accent, fraction: 1)
                .onTapGesture { target = 0 }
            CrownField(label: "New distance", value: $distance, unit: "m",
                       step: 0.5, range: 0.5...100, targeted: target == 1, accent: accent, fraction: 1)
                .onTapGesture { target = 1 }
        }
    }
}

private struct SabineWatch: View {
    let accent: Color
    @State private var volume: Double = 200
    @State private var absorption: Double = 40
    @State private var target = 0

    private var rt60: Double { Acoustics.sabineRT60(volumeM3: volume, absorptionSabins: max(absorption, 0.01)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "RT60 (Sabine)", value: Fmt.f(rt60, 2), unit: "s", accent: accent, hero: true)
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

private struct LevelsWatch: View {
    let accent: Color
    @State private var db: Double = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedReadout(label: "Voltage ratio", value: Fmt.f(Levels.voltageRatio(db: db), 3),
                           unit: "×", accent: accent, hero: true)
            StackedReadout(label: "Power ratio", value: Fmt.f(Levels.powerRatio(db: db), 3), unit: "×")
            CrownField(label: "Level", value: $db, unit: "dB",
                       step: 0.5, range: -60...60, targeted: true, accent: accent, fraction: 1)
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
                           unit: "dB", accent: accent, hero: true)
            StackedReadout(label: "Right gain", value: Fmt.f(Levels.voltageDB(ratio: max(g.right, 1e-6)), 1), unit: "dB")
            CrownField(label: "Pan", value: $position, unit: "",
                       step: 0.05, range: -1...1, targeted: true, accent: accent, fraction: 2)
        }
    }
}
