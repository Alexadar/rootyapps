import SwiftUI

// Replaces Components.swift. Same call sites (`NumberField`, `ResultRow`),
// restyled for the light theme; adds `StepperRow` (glove-XL input) and `CheckRow`
// (code-check pill) used by the redesigned tool detail screens.

/// Labeled numeric input — value is a monospaced chip (decimal pad on iOS).
/// Kept for compatibility; prefer `StepperRow` on primary field screens.
struct NumberField: View {
    let title: String
    @Binding var value: Double
    var unit: String = ""
    var range: ClosedRange<Double>? = nil

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
/// Hit targets are 38–44pt so it's usable in work gloves. `−` is the light key,
/// `+` is the graphite key — the same two-weight language as the keypad.
struct StepperRow: View {
    let title: String
    @Binding var value: Double
    var unit: String = ""
    var step: Double = 1
    var range: ClosedRange<Double> = 0...9_999
    /// Formats the value; default shows up to 2 decimals, trimming trailing zeros.
    var format: (Double) -> String = { v in
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }

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
            }.buttonStyle(.plain)

            Text(format(value))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .frame(minWidth: 58)

            Button { nudge(1) } label: {
                Image(systemName: "plus").font(.title3.weight(.bold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(KC.onInstrument)
                    .background(KC.instrument, in: .rect(cornerRadius: KC.rInput))
            }.buttonStyle(.plain)

            if !unit.isEmpty {
                Text(unit).font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(KC.textTertiary)
                    .frame(width: 26, alignment: .leading)
            }
        }
    }
}

/// Read-only result row: label ↔ monospaced value.
/// `emphasis` tints the value in the section accent (readable on a light card);
/// the *big* hero number uses `HeroReadout`, not this.
struct ResultRow: View {
    let label: String
    let value: String
    var unit: String = ""
    var emphasis: Bool = false
    var tone: Color? = nil

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
    }
}

/// A single code-check line: label ↔ OK / CHECK pill. Green = pass, coral = review.
struct CheckRow: View {
    let label: String
    let passing: Bool
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
    }
}
