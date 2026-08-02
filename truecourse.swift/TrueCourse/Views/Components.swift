import SwiftUI

// Replaces Components.swift. Same call sites; restyled, theme-aware internals.

/// Labeled numeric input — the value is a monospaced chip with a fixed-width unit and an
/// inline range hint. Focused state shows the section-accent ring (set `.tint(calc.accent)`).
struct NumberField: View {
    @Environment(\.tc) private var tc
    let title: String
    @Binding var value: Double
    var unit: String = ""
    var range: ClosedRange<Double>? = nil
    /// Fields that accept negatives (temperatures, ISA deviation) need a keyboard with a
    /// minus sign — `.decimalPad` has none. Set true on any field whose range goes below 0.
    var allowsNegative: Bool = false
    @FocusState private var focused: Bool

    /// Clamp the committed value into the field's valid domain (its `InputBounds` range),
    /// so an out-of-range entry (e.g. altimeter 99 inHg) can never reach the math.
    private var bound: Binding<Double> {
        Binding(get: { value },
                set: { v in value = range.map { Swift.min(Swift.max(v, $0.lowerBound), $0.upperBound) } ?? v })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(tc.textTertiary)
                Spacer()
                if let range {
                    Text("\(Int(range.lowerBound))–\(Int(range.upperBound))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(tc.textTertiary)
                }
            }
            HStack(spacing: 12) {
                TextField(title, value: bound, format: .number)
                    .focused($focused)
                    .accessibilityIdentifier("field.\(title)")
                    .multilineTextAlignment(.leading)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tc.textPrimary)
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .keyboardType(allowsNegative ? .numbersAndPunctuation : .decimalPad)
                    #endif
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(tc.textSecondary)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(tc.pressed, in: .rect(cornerRadius: TC.rChip))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(minHeight: TC.minHit)
            .background(tc.surfaceRaised, in: .rect(cornerRadius: TC.rField))
            .overlay(
                RoundedRectangle(cornerRadius: TC.rField)
                    .strokeBorder(focused ? AnyShapeStyle(.tint) : AnyShapeStyle(tc.hairline),
                                  lineWidth: focused ? 1.5 : 1)
            )
            .background {
                if focused {   // soft accent halo
                    RoundedRectangle(cornerRadius: TC.rField)
                        .fill(.tint).opacity(0.18).blur(radius: 6)
                }
            }
        }
    }
}

/// Read-only result row: label ↔ monospaced value.
/// `emphasis` renders the one hero readout per screen — large, tabular, in the section accent.
struct ResultRow: View {
    @Environment(\.tc) private var tc
    let label: String
    let value: String
    var unit: String = ""
    var emphasis: Bool = false

    var body: some View {
        if emphasis { hero } else { row }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(tc.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: 54, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(tc.textPrimary)   // digits stay max-contrast; accent is the rule
                    .minimumScaleFactor(0.5)           // scales with Dynamic Type
                    .lineLimit(1)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(tc.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("result.\(label)")
            .accessibilityLabel(label)
            .accessibilityValue(a11yValue)
        }
    }

    /// The exact readout string a UI test asserts (value plus unit).
    private var a11yValue: String { unit.isEmpty ? value : "\(value) \(unit)" }

    private var row: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(tc.textSecondary)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .foregroundStyle(tc.textPrimary)
                if !unit.isEmpty {
                    Text(unit).font(.footnote).foregroundStyle(tc.textTertiary)
                }
            }
            .monospacedDigit()
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("result.\(label)")
        .accessibilityLabel(label)
        .accessibilityValue(a11yValue)
    }
}
