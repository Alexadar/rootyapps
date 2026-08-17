import SwiftUI

// watchOS 26 — Overtone Lab on the wrist. Dark only, no light variant.
// Inherits OTL tokens + ToolSection.accent unchanged; the math packages compile as-is.
// Curated to 7 tools: tempo, delay, pitch, spl, sabine, levels, pan.

// MARK: - Curation

extension Tool {
    /// The only tools that ship on watchOS. Everything else stays on phone/Mac.
    static let watchTools: [Tool] = [.tempo, .delay, .pitch, .spl, .sabine, .levels, .pan]
    var shipsOnWatch: Bool { Self.watchTools.contains(self) }
}

// MARK: - Front door (direction 1d — "Straight In")

/// Opens on the last-used tool, already showing a number: zero taps.
/// Swipe (or crown-page) between the seven; long-press opens the picker.
struct WatchRootView: View {
    @AppStorage("otl.watch.lastTool") private var lastToolID: String = Tool.tempo.rawValue

    private var selection: Binding<Tool> {
        Binding(get: { Tool(rawValue: lastToolID) ?? .tempo },
                set: { lastToolID = $0.rawValue })
    }

    var body: some View {
        TabView(selection: selection) {
            ForEach(Tool.watchTools) { tool in
                WatchToolView(tool: tool)
                    .tag(tool)
            }
        }
        .tabViewStyle(.verticalPage)     // page dots teach the seven on first run
        .background(Color.black)
    }
}

// MARK: - Tool screen

/// Label ABOVE value, never a side-by-side row: German compounds
/// ("Nachhallzeit", "Raumvolumen") break a row but only make a stack taller.
struct WatchToolView: View {
    let tool: Tool
    @State private var crownTarget: Int = 0
    @State private var volume: Double = 200      // m³
    @State private var absorption: Double = 40   // sabins

    private var rt60: Double { 0.161 * volume / max(absorption, 0.001) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: tool.symbol).foregroundStyle(tool.accent)
                    Text(tool.title).font(.headline)
                }

                // Hero — exactly one per screen, in the section accent.
                StackedReadout(
                    label: "Reverberation time",           // localised; never CSS-uppercased
                    value: rt60.formatted(.number.precision(.fractionLength(2))),
                    unit: "s",
                    accent: tool.accent,
                    hero: true
                )

                StackedReadout(label: "Schroeder frequency", value: "127", unit: "Hz",
                               accent: OTL.textPrimary, hero: false)

                CrownField(label: "Room volume", value: $volume, unit: "m³",
                           step: 5, range: 10...2000,          // 5 m³ — rooms are estimated
                           targeted: crownTarget == 0, accent: tool.accent)
                    .onTapGesture { crownTarget = 0 }

                CrownField(label: "Absorption ΣSα", value: $absorption, unit: "sabins",
                           step: 1, range: 1...500,
                           targeted: crownTarget == 1, accent: tool.accent)
                    .onTapGesture { crownTarget = 1 }
            }
            .padding(.horizontal, 10)
        }
        .background(
            RadialGradient(colors: [tool.accent.opacity(0.15), .clear],
                           center: .top, startRadius: 0, endRadius: 150)
                .ignoresSafeArea()
        )
        .containerBackground(tool.accent.gradient.opacity(0.2), for: .tabView)
    }
}

/// Stacked label-over-value. `hero` renders the one big honest number.
struct StackedReadout: View {
    let label: LocalizedStringKey
    let value: String
    let unit: String
    let accent: Color
    let hero: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(OTL.textSecondary)
                .minimumScaleFactor(0.85)       // never truncate a localised label
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(hero ? .largeTitle : .headline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(hero ? accent : OTL.textPrimary)
                Text(unit)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(OTL.textTertiary)
            }
            .monospacedDigit()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text("\(value) \(unit)"))
        }
    }
}

/// A tappable card that becomes the Digital Crown's target (accent ring).
/// Two-tier acceleration only — fine detent, fast spin. No third speed.
struct CrownField: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    let unit: String
    let step: Double
    let range: ClosedRange<Double>
    let targeted: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(OTL.textSecondary)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                // .formatted() honours the user locale → a German user sees 0,81
                Text(value.formatted(.number.precision(.fractionLength(0...1))))
                    .font(.system(.headline, design: .monospaced).weight(.semibold))
                Text(unit)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(OTL.textTertiary)
                Spacer()
                if targeted {
                    Text("CROWN")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(accent)
                }
            }
            .monospacedDigit()
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)                       // hit target
        .background(OTL.surface, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(targeted ? accent.opacity(0.4) : OTL.hairline, lineWidth: 1)
        )
        .focusable(targeted)
        .digitalCrownRotation($value, from: range.lowerBound, through: range.upperBound,
                              by: step, sensitivity: .medium,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .accessibilityValue(Text(value.formatted() + " " + unit))
    }
}

// MARK: - Tap tempo (the one input the wrist does better than the phone)

@MainActor
final class TapTempo: ObservableObject {
    @Published private(set) var bpm: Double = 120
    private var taps: [Date] = []

    func tap() {
        let now = Date()
        if let last = taps.last, now.timeIntervalSince(last) > 2 { taps.removeAll() }
        taps.append(now)
        if taps.count > 9 { taps.removeFirst(taps.count - 9) }
        guard taps.count >= 4 else { return }               // need 4 taps to lock
        let intervals = zip(taps.dropFirst(), taps).map { $0.timeIntervalSince($1) }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        bpm = (60 / mean * 2).rounded() / 2                 // ±0.5 BPM
    }
}
