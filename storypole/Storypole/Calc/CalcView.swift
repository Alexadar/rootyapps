import SwiftUI
import DimensionKit

/// The front door: the keypad, the readout, and the tape.
///
/// Every key is live at every moment. In particular **Feet and Inch never grey out**, which is the
/// incumbent's twelve-year defect — *"I hit the 'X' multiplication symbol then go to put in the
/// 2nd measurement ... the FEET and INCHES buttons are GRAYED OUT"* (2★ 2014-08-04).
@MainActor
final class CalcModel: ObservableObject {
    @Published var calc = TapeCalc()
    @Published var history: [String] = []

    var denominator: Int64 {
        get { calc.denominator }
        set { calc.setDenominator(newValue) }
    }

    func press(_ k: Key) {
        switch k {
        case .digit(let d):  calc.digit(d)
        case .feet:          calc.feetKey()
        case .inch:          calc.inchKey()
        case .fraction:      calc.fractionKey()
        case .op(let o):     calc.setOp(o)
        case .equals:
            calc.equals()
            let text = readout
            if history.last != text { history.append(text) }
            if history.count > 40 { history.removeFirst() }
        case .clear:         calc.clear()
        case .backspace:     calc.backspace()
        }
    }

    /// Recall a previous line into the current calculation — 5★ 2020-04-17:
    /// *"I would like to be able click on a measurement I just calculated and be able to add or
    /// subtract from that as well"*.
    func recall(_ line: String) {
        guard let v = FeetInch.parse(line) else { return }
        calc.preload(v)
    }

    /// Seed a representative calculation for capture — see `STORYPOLE_DEMO` in `CalcView`.
    /// Runs the real keypad, so what a screenshot shows is genuinely what the app computes.
    func seedDemo() {
        guard history.isEmpty else { return }
        calc = TapeCalc()
        for k: Key in [.digit(6), .feet, .digit(2), .inch, .digit(1), .fraction, .digit(2)] { press(k) }
        press(.op(.add))
        for k: Key in [.digit(2), .feet, .digit(7), .inch, .digit(3), .fraction, .digit(4)] { press(k) }
        press(.equals)
    }

    /// A measurement set by dragging the blade. The value has already been snapped to the
    /// denominator and clamped to the tape by `Tape.scrubbing(…)` — this only stores it.
    func scrub(to v: FeetInch) {
        calc.preload(v)
    }

    var readout: String {
        switch calc.currentDimension {
        case .square: return calc.areaFt2.map { Fmt.trim($0) + " sq ft" } ?? "0"
        case .cubic:  return calc.volumeFt3.map { Fmt.trim($0) + " cu ft" } ?? "0"
        case .scalar: return Fmt.trim(calc.displayValue.inchesValue)
        case .linear: return calc.displayValue.formatted(toDenominator: calc.denominator)
        }
    }

    var decimalReadout: String {
        calc.currentDimension == .linear ? calc.displayValue.formattedDecimalInches() : ""
    }

    enum Key: Hashable {
        case digit(Int), feet, inch, fraction, op(TapeCalc.Op), equals, clear, backspace
    }
}

/// The front door: the plaque, the blade, and the keypad.
///
/// `CalcModel` is unchanged from the shipping build — the design layer restyles and re-lays-out,
/// it does not touch arithmetic. Every key is live at every moment; in particular **feet and inch
/// never grey out**, which is the incumbent's twelve-year defect.
struct CalcView: View {
    @StateObject private var m = CalcModel()

    /// `STORYPOLE_DEMO=1` seeds a representative calculation at launch.
    ///
    /// Purely for capture: a store screenshot of the front door showing `0"` wastes the most
    /// valuable frame the listing has. This puts a real mixed-fraction answer on the plaque and a
    /// mark on the blade — `6' 2-1/2" + 2' 7-3/4" = 8' 10-1/4"` — which is exactly the job the app
    /// is bought for. It changes nothing in a normal launch.
    private var demoRequested: Bool {
        LaunchOverride.flag("STORYPOLE_DEMO")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SP.s3) {
                Readout(value: m.readout, decimal: m.decimalReadout, error: m.calc.error?.rawValue)

                VStack(alignment: .leading, spacing: SP.s3) {
                    // The blade is also an input. Scrubbing behaves exactly like typing: after `=`
                    // it starts a fresh entry rather than silently editing the result you just
                    // computed, which is the same rule the digit keys follow.
                    TapeView(value: m.calc.displayValue,
                             denominator: m.denominator,
                             onScrub: { m.scrub(to: $0) })
                }
                .spCard()

                DenominatorPicker(denominator: Binding(get: { m.denominator },
                                                      set: { m.denominator = $0 }))
                keypad

                if !m.history.isEmpty { historyStrip }
            }
            .padding(SP.s4)
            // iOS 26's tab bar floats OVER the scroll content, so the last card was clipped in
            // half — visible in the very first store screenshot. Give the content room to scroll
            // clear of it.
            .padding(.bottom, SP.s5 * 2)
        }
        .background(SP.background)
        .navigationTitle("Storypole")
        .onAppear { if demoRequested { m.seedDemo() } }
    }

    // MARK: Keypad

    private let rows: [[CalcModel.Key]] = [
        [.digit(7), .digit(8), .digit(9), .op(.div)],
        [.digit(4), .digit(5), .digit(6), .op(.mul)],
        [.digit(1), .digit(2), .digit(3), .op(.sub)],
        [.digit(0), .fraction, .backspace, .op(.add)],
        [.feet, .inch, .clear, .equals],
    ]

    private var keypad: some View {
        VStack(spacing: SP.s2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: SP.s2) {
                    ForEach(row, id: \.self) { key in
                        Button { m.press(key) } label: { Text(label(key)) }
                            .buttonStyle(KeyStyle(kind: kind(key)))
                            .accessibilityIdentifier("key." + identifier(key))
                    }
                }
            }
        }
    }

    private func label(_ k: CalcModel.Key) -> String {
        switch k {
        case .digit(let d): return String(d)
        case .feet:         return "ft"
        case .inch:         return "in"
        case .fraction:     return "/"        // numerator FIRST, then this key, then denominator
        case .op(let o):    return o.rawValue
        case .equals:       return "="
        case .clear:        return "C"
        case .backspace:    return "⌫"
        }
    }

    private func identifier(_ k: CalcModel.Key) -> String {
        switch k {
        case .digit(let d): return "digit\(d)"
        case .feet:         return "feet"
        case .inch:         return "inch"
        case .fraction:     return "fraction"
        case .op(let o):    return "op." + String(describing: o)
        case .equals:       return "equals"
        case .clear:        return "clear"
        case .backspace:    return "backspace"
        }
    }

    private func kind(_ k: CalcModel.Key) -> KeyStyle.Kind {
        switch k {
        case .op, .equals:            return .accent
        case .feet, .inch, .fraction: return .tagged
        default:                      return .plain
        }
    }

    // MARK: History — the paper tape, tappable back into the calculation

    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: SP.s2) {
            SectionEyebrow(title: "Tape", accent: SP.accent)
            ForEach(Array(m.history.suffix(6).reversed().enumerated()), id: \.offset) { _, line in
                Button { m.recall(line) } label: {
                    HStack {
                        Text(line).font(SPType.valueSm).foregroundStyle(SP.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.uturn.left")
                            .font(SPType.footnote)
                            .foregroundStyle(SP.textTertiary)
                    }
                    .frame(minHeight: 36)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .spCard()
        .accessibilityIdentifier("calc.history")
    }
}

#Preview         { NavigationStack { CalcView() } }
#Preview("Dark")  { NavigationStack { CalcView() }.preferredColorScheme(.dark) }
