import SwiftUI
import WatchKit
import DimensionKit
import PitchKit
import GeometryKit
import LumberKit
import GaugeKit

// MARK: - Paging model

/// Two states, one at a time: the catalog, or one tool.
///
/// There is deliberately **no paging between tools**. `overtonelab` tried it twice and removed it:
/// vertical paging fights the Digital Crown for every turn, so a crown twist meant to change a
/// value moves the screen instead. Removing it hands the crown back to the fields, which here is
/// the only thing it should ever drive — entering a fraction.
enum WatchPage: Hashable {
    case list
    case tool(Tool)
}

// MARK: - Front door

/// Opens on the last-used tool, already showing a number: zero taps to an answer.
struct WatchRootView: View {
    @AppStorage("sp.watch.lastTool") private var lastToolID: String = Tool.tapeCalc.rawValue
    @State private var page: WatchPage = .list

    /// `STORYPOLE_WATCH_TOOL=list` shows the catalog — the one screen that is not a tool.
    private func raw_isList() -> Bool {
        LaunchOverride.value("STORYPOLE_WATCH_TOOL") == "list"
    }

    var body: some View {
        ZStack {
            SP.background.ignoresSafeArea()
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
            // STORYPOLE_WATCH_TOOL pins the screen for capture; otherwise resume the last tool.
            if let raw = LaunchOverride.value("STORYPOLE_WATCH_TOOL"),
               let t = Tool(rawValue: raw), t.onWatch {
                page = .tool(t)
            } else if raw_isList() {
                page = .list
            } else if let last = Tool(rawValue: lastToolID), last.onWatch {
                page = .tool(last)
            }
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
            VStack(alignment: .leading, spacing: SP.s2) {
                // The header IS the way back to the catalog.
                Button { page = .list } label: {
                    HStack(spacing: SP.s1) {
                        Image(systemName: tool.symbol).foregroundStyle(tool.section.accent)
                        Text(tool.title)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(SP.textSecondary)
                        Spacer(minLength: 2)
                        Image(systemName: "list.bullet")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(tool.section.accent)
                            .frame(width: 32, height: 32)
                            .background(tool.section.accent.opacity(0.16), in: .circle)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("All tools"))

                body(for: tool)
            }
            .padding(.horizontal, SP.s2)
            .padding(.bottom, SP.s2)
        }
        // Swipe left-to-right → the catalog, the direction watchOS uses for "back" everywhere else.
        // simultaneousGesture so the screen still scrolls; the 2:1 test keeps a diagonal scroll
        // from being read as a sideways flick.
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

    // Split in two: a single switch over every tool in one `body` blows past the type-checker's
    // expression limit and the compiler reports it as an unrelated error miles away.
    @ViewBuilder private func body(for tool: Tool) -> some View {
        switch tool.section {
        case .tape, .roof: firstHalf(tool)
        default:           secondHalf(tool)
        }
    }

    @ViewBuilder private func firstHalf(_ tool: Tool) -> some View {
        switch tool {
        case .tapeCalc:  TapeCalcWatch(accent: tool.section.accent)
        case .convert:   ConvertWatch(accent: tool.section.accent)
        case .roofPitch: RoofPitchWatch(accent: tool.section.accent)
        default:         EmptyView()
        }
    }

    @ViewBuilder private func secondHalf(_ tool: Tool) -> some View {
        switch tool {
        case .diagonal:  DiagonalWatch(accent: tool.section.accent)
        case .circle:    CircleWatch(accent: tool.section.accent)
        case .boardFeet: BoardFeetWatch(accent: tool.section.accent)
        case .wireGauge: WireGaugeWatch(accent: tool.section.accent)
        default:         EmptyView()
        }
    }
}

// MARK: - The hero: a running tape total

/// Add and subtract measurements with the crown, read the running total as a fraction.
/// This is the whole reason the watch app exists.
struct TapeCalcWatch: View {
    let accent: Color
    @State private var entrySixteenths: Double = 16 * 12          // 1 ft
    @State private var total = FeetInch.zero
    @State private var scale: CrownScale = .inch
    /// The crown only drives a view that HOLDS focus. The scale chips are Buttons and take it on
    /// tap, so focus is handed back explicitly — otherwise the crown goes dead, the entry keeps its
    /// old value, and Add/Sub silently apply the same amount every time.
    @FocusState private var crownFocused: Bool

    private var entry: FeetInch { FeetInch(inches: Rational(Int64(entrySixteenths.rounded()), 16)) }

    /// `STORYPOLE_DEMO=1` seeds a running total for capture. A watch screenshot whose hero number
    /// is `0"` wastes the one line the whole screen is for — same reason the phone has this hook.
    private var demoTotal: FeetInch? {
        LaunchOverride.flag("STORYPOLE_DEMO")
            ? FeetInch(feet: 8, inches: 10, num: 1, den: 4) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s2) {
            StackedReadout(label: "Running total", value: total.formatted(toDenominator: 16),
                           accent: accent, hero: true)

            CrownScalePicker(scale: $scale, accent: accent) { crownFocused = true }

            TapeCrownField(label: "Add / subtract",
                           sixteenths: $entrySixteenths, targeted: true, accent: accent,
                           stepSixteenths: scale.sixteenths)
                .focused($crownFocused)

            HStack(spacing: SP.s2) {
                Button {
                    total = total + entry
                    crownFocused = true
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity)
                }
                .tint(accent)
                .accessibilityIdentifier("watch.add")
                Button {
                    total = total - entry
                    crownFocused = true
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    Label("Sub", systemImage: "minus")
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity)
                }
                .tint(SP.textSecondary)
                .accessibilityIdentifier("watch.sub")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) { total = .zero; crownFocused = true } label: {
                Text("Clear")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("watch.clear")

            if let tape = Tape.smallest(for: total) {
                StackedReadout(label: "Fits", value: "\(tape.lengthFeet) ft tape")
            }
        }
        .onAppear {
            crownFocused = true
            if let d = demoTotal, total == .zero { total = d }
        }
    }
}

// MARK: - The rest of the seven

struct ConvertWatch: View {
    let accent: Color
    @State private var sixteenths: Double = 16 * 12
    @State private var scale: CrownScale = .inch
    @FocusState private var crownFocused: Bool

    private var v: FeetInch { FeetInch(inches: Rational(Int64(sixteenths.rounded()), 16)) }

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s2) {
            StackedReadout(label: "Feet & inches", value: v.formatted(toDenominator: 16),
                           accent: accent, hero: true)
            CrownScalePicker(scale: $scale, accent: accent) { crownFocused = true }
            TapeCrownField(label: "Measurement", sixteenths: $sixteenths, targeted: true,
                           accent: accent, stepSixteenths: scale.sixteenths)
                .focused($crownFocused)
            StackedReadout(label: "Millimetres",
                           value: Fmt.f(Units.convert(v.inchesValue, from: .inch, to: .millimeter), 1),
                           unit: "mm")
            StackedReadout(label: "Metres",
                           value: Fmt.f(Units.convert(v.inchesValue, from: .inch, to: .meter), 3), unit: "m")
            StackedReadout(label: "Decimal inches", value: Fmt.f(v.inchesValue, 3), unit: "in")
        }
        .onAppear { crownFocused = true }
    }
}

struct RoofPitchWatch: View {
    let accent: Color
    @State private var rise = 6.0

    var body: some View {
        VStack(alignment: .leading, spacing: SP.s2) {
            StackedReadout(label: "Angle", value: Fmt.f(Pitch.angleFromPitch(riseIn12: rise), 2),
                           unit: "°", accent: accent, hero: true)
            WatchNumberField(label: "Rise in 12", value: $rise, unit: "in", step: 0.5, range: 0...36,
                             targeted: true, accent: accent, places: 1)
            StackedReadout(label: "Slope", value: Fmt.f(Pitch.slopePercent(rise: rise, run: 12), 1), unit: "%")
            StackedReadout(label: "Multiplier", value: Fmt.f(Pitch.pitchMultiplier(riseIn12: rise), 4))
        }
    }
}

struct DiagonalWatch: View {
    let accent: Color
    @State private var aSixteenths: Double = 16 * 36
    @State private var bSixteenths: Double = 16 * 48
    @State private var targetA = true
    @State private var scale: CrownScale = .inch
    @FocusState private var crownFocused: Bool

    var body: some View {
        let a = FeetInch(inches: Rational(Int64(aSixteenths.rounded()), 16))
        let b = FeetInch(inches: Rational(Int64(bSixteenths.rounded()), 16))
        let d = Diagonal.hypotenuse(a.inchesValue, b.inchesValue)

        VStack(alignment: .leading, spacing: SP.s2) {
            StackedReadout(label: "Diagonal",
                           value: FeetInch.approx(inches: d, den: 16).formatted(toDenominator: 16),
                           accent: accent, hero: true)
            CrownScalePicker(scale: $scale, accent: accent) { crownFocused = true }
            TapeCrownField(label: "Side A", sixteenths: $aSixteenths, targeted: targetA,
                           accent: accent, stepSixteenths: scale.sixteenths)
                .focused($crownFocused, equals: targetA)
                .onTapGesture { targetA = true; crownFocused = true }
            TapeCrownField(label: "Side B", sixteenths: $bSixteenths, targeted: !targetA,
                           accent: accent, stepSixteenths: scale.sixteenths)
                .focused($crownFocused, equals: !targetA)
                .onTapGesture { targetA = false; crownFocused = true }
        }
        .onAppear { crownFocused = true }
    }
}

struct CircleWatch: View {
    let accent: Color
    @State private var sixteenths: Double = 16 * 4
    @State private var scale: CrownScale = .sixteenth
    @FocusState private var crownFocused: Bool

    var body: some View {
        let d = FeetInch(inches: Rational(Int64(sixteenths.rounded()), 16))
        let c = Circle.circumference(diameter: d.inchesValue)
        VStack(alignment: .leading, spacing: SP.s2) {
            StackedReadout(label: "Wrap",
                           value: FeetInch.approx(inches: c, den: 16).formatted(toDenominator: 16),
                           accent: accent, hero: true)
            CrownScalePicker(scale: $scale, accent: accent) { crownFocused = true }
            TapeCrownField(label: "Diameter", sixteenths: $sixteenths, targeted: true,
                           accent: accent, stepSixteenths: scale.sixteenths)
                .focused($crownFocused)
            StackedReadout(label: "Decimal", value: Fmt.f(c, 3), unit: "in")
        }
        .onAppear { crownFocused = true }
    }
}

struct BoardFeetWatch: View {
    let accent: Color
    @State private var thickness = 2.0
    @State private var width = 4.0
    @State private var lengthFt = 8.0
    @State private var target = 2

    var body: some View {
        let bf = BoardFeet.value(thicknessIn: thickness, widthIn: width, lengthFt: lengthFt)
        VStack(alignment: .leading, spacing: SP.s2) {
            StackedReadout(label: "Board feet", value: Fmt.f(bf, 2), unit: "BF",
                           accent: accent, hero: true)
            WatchNumberField(label: "Thickness", value: $thickness, unit: "in", step: 0.5,
                             range: 0.5...12, targeted: target == 0, accent: accent, places: 1)
                .onTapGesture { target = 0 }
            WatchNumberField(label: "Width", value: $width, unit: "in", step: 1,
                             range: 1...24, targeted: target == 1, accent: accent)
                .onTapGesture { target = 1 }
            WatchNumberField(label: "Length", value: $lengthFt, unit: "ft", step: 1,
                             range: 1...40, targeted: target == 2, accent: accent)
                .onTapGesture { target = 2 }
            Text("Nominal sizes, per NIST PS 20-20 §2.2.")
                .font(.system(size: 10)).foregroundStyle(SP.textTertiary)
        }
    }
}

struct WireGaugeWatch: View {
    let accent: Color
    @State private var gage = 12.0

    var body: some View {
        let n = Int(gage.rounded())
        VStack(alignment: .leading, spacing: SP.s2) {
            StackedReadout(label: AWG.name(gage: n) == "" ? "Diameter" : "Diameter",
                           value: Fmt.f(AWG.diameterInch(gage: n), 4), unit: "in",
                           accent: accent, hero: true)
            WatchNumberField(label: "Gage", value: $gage, step: 1, range: -3...36,
                             targeted: true, accent: accent)
            StackedReadout(label: "Millimetres", value: Fmt.f(AWG.diameterMillimetres(gage: n), 3), unit: "mm")
            Text("Dimension only — never ampacity.")
                .font(.system(size: 10)).foregroundStyle(SP.textTertiary)
        }
    }
}

#Preview("Tape total") { ScrollView { TapeCalcWatch(accent: SP.accent).padding(8) } }
#Preview("Convert")    { ScrollView { ConvertWatch(accent: SP.accent).padding(8) } }
