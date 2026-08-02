import SwiftUI
import DimensionKit

/// The front door: the plaque, the blade, and the keypad.
///
/// `CalcModel` is unchanged from the shipping build — the design layer restyles and re-lays-out,
/// it does not touch arithmetic. Every key is live at every moment; in particular **feet and inch
/// never grey out**, which is the incumbent's twelve-year defect.
struct CalcView: View {
    @StateObject private var m = CalcModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SP.s3) {
                Readout(value: m.readout, decimal: m.decimalReadout, error: m.calc.error?.rawValue)

                VStack(alignment: .leading, spacing: SP.s3) {
                    TapeView(value: m.calc.displayValue, denominator: m.denominator)
                }
                .spCard()

                DenominatorPicker(denominator: Binding(get: { m.denominator },
                                                      set: { m.denominator = $0 }))
                keypad

                if !m.history.isEmpty { historyStrip }
            }
            .padding(SP.s4)
        }
        .background(SP.background)
        .navigationTitle("Storypole")
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
            ForEach(Array(rows.enumerated()), id: .offset) { _, row in
                HStack(spacing: SP.s2) {
                    ForEach(row, id: .self) { key in
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
        case .digit(let d): return "digit(d)"
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
            ForEach(Array(m.history.suffix(6).reversed().enumerated()), id: .offset) { _, line in
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
