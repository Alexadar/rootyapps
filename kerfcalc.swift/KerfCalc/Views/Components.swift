import SwiftUI

// NumberField (restyled), StepperRow (glove-XL), ResultRow, CheckRow.
// SubScreenPicker lives in KCSegmented.swift.

/// Labeled numeric input — value is a monospaced chip (decimal pad on iOS).
struct NumberField: View {
    let title: String
    @Binding var value: Double
    var unit: String = ""
    var range: ClosedRange<Double>? = nil
    /// Test handle, e.g. `input.pitch.rise`.
    var identifier: String? = nil

    private var bound: Binding<Double> {
        Binding(get: { value },
                set: { v in value = range.map { min(max(v, $0.lowerBound), $0.upperBound) } ?? v })
    }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(KC.textPrimary)
            Spacer()
            TextField(title, value: bound, format: .number)
                .multilineTextAlignment(.trailing)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .frame(minWidth: 44)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(KC.chipFill, in: .rect(cornerRadius: KC.rChip))
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .textFieldStyle(.plain)
                // On the TextField itself, not the row: a test types into it, and a container id
                // would hide the field from the query that needs to tap it.
                .accessibilityIdentifier(identifier ?? "number")
            if !unit.isEmpty {
                Text(unit).font(.footnote)
                    .foregroundStyle(KC.textTertiary)
                    .frame(width: 40, alignment: .leading)
            }
        }
        .font(.callout)
    }
}

/// Glove-XL input: label ↔ big −/+ steppers around a monospaced value.
/// `−` is the light key, `+` is the graphite key — the same two-weight language as the keypad.
struct StepperRow: View {
    let title: String
    @Binding var value: Double
    var unit: String = ""
    var step: Double = 1
    var range: ClosedRange<Double> = 0...9_999
    var format: (Double) -> String = { v in
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }
    /// Test handle prefix, e.g. `input.rafter.pitch` → `.dec` / `.inc` / `.value`.
    ///
    /// The ids used to be the hardcoded constants `stepDec`/`stepInc`, and the Rafter screen has TWO
    /// StepperRows — so both minus buttons answered to the same id and a test could only reach the
    /// first via `.firstMatch`. Derive them from the row instead.
    var identifier: String? = nil

    private var idBase: String { identifier ?? "step" }

    private func nudge(_ dir: Double) {
        value = min(range.upperBound, max(range.lowerBound, (value + dir * step)))
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KC.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { nudge(-1) } label: {
                Image(systemName: "minus").font(.title3.weight(.bold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(KC.textPrimary)
                    .background(KC.chipFill, in: .rect(cornerRadius: KC.rInput))
                    .overlay(RoundedRectangle(cornerRadius: KC.rInput).strokeBorder(KC.hairline, lineWidth: 1))
            }.buttonStyle(.plain).accessibilityIdentifier("\(idBase).dec")

            Text(format(value))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .frame(minWidth: 58)
                .accessibilityIdentifier("\(idBase).value")

            Button { nudge(1) } label: {
                Image(systemName: "plus").font(.title3.weight(.bold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(KC.onInstrument)
                    .background(KC.instrument, in: .rect(cornerRadius: KC.rInput))
            }.buttonStyle(.plain).accessibilityIdentifier("\(idBase).inc")

            if !unit.isEmpty {
                Text(unit).font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(KC.textTertiary)
                    .frame(width: 26, alignment: .leading)
            }
        }
    }
}

/// Read-only result row: label ↔ monospaced value.
/// `emphasis` tints the value in the section accent; the *big* hero number uses `HeroReadout`.
struct ResultRow: View {
    let label: String
    let value: String
    var unit: String = ""
    var emphasis: Bool = false
    var tone: Color? = nil
    /// Test handle, e.g. `rafter.ridge`. Named explicitly because `.combine` below would otherwise
    /// leave macOS to synthesise a joined identifier from the children.
    var identifier: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(KC.textSecondary)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(emphasis
                          ? .system(.title3, design: .monospaced).weight(.semibold)
                          : .system(.callout, design: .monospaced).weight(.medium))
                    .foregroundStyle(tone.map(AnyShapeStyle.init)
                                     ?? (emphasis ? AnyShapeStyle(.tint) : AnyShapeStyle(KC.textPrimary)))
                if !unit.isEmpty {
                    Text(unit).font(.footnote).foregroundStyle(KC.textTertiary)
                }
            }
            .monospacedDigit()
        }
        .font(.callout)
        // `.combine` is right HERE (unlike HeroReadout): "Ridge, 14 ft" is one thing a user reads,
        // and combining also makes `element.text` return the whole row on macOS, where a plain Text
        // leaf has an EMPTY label and hides its string in `value`.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier ?? "result")
    }
}

/// A single code-check line: label ↔ OK / CHECK pill. Green = pass, coral = review.
struct CheckRow: View {
    let label: String
    let passing: Bool
    /// Test handle, e.g. `stairs.riserCheck`. Without one a test can only look for the literal
    /// "OK"/"CHECK", and three of these on the Stairs screen are then indistinguishable.
    var identifier: String? = nil

    var body: some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(KC.textSecondary)
            Spacer()
            Text(passing ? "OK" : "CHECK")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(passing ? KC.ok : KC.warn)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background((passing ? KC.ok : KC.warn).opacity(0.12), in: .rect(cornerRadius: KC.rChip))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier ?? "check")
    }
}

/// Initial sub-screen from the screenshot env hook.
func initialScreen() -> Int { Int(LaunchOverride.value("KERFCALC_SCREEN") ?? "0") ?? 0 }
