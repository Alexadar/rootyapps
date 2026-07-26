import SwiftUI

// Replaces Components.swift. Same call sites; restyled internals.

/// Labeled numeric input — the value is a monospaced chip (decimal pad on iOS).
struct NumberField: View {
    let title: String
    @Binding var value: Double
    var unit: String = ""
    var body: some View {
        HStack {
            Text(title).foregroundStyle(OTL.textPrimary)
            Spacer()
            TextField(title, value: $value, format: .number)
                .multilineTextAlignment(.trailing)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .frame(minWidth: 44)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(OTL.chipFill, in: .rect(cornerRadius: OTL.rChip))
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .textFieldStyle(.plain)
            if !unit.isEmpty {
                Text(unit)
                    .font(.footnote)
                    .foregroundStyle(OTL.textTertiary)
                    .frame(width: 40, alignment: .leading)
            }
        }
        .font(.callout)
    }
}

/// Read-only result row: label ↔ monospaced value.
/// `emphasis` renders the one hero readout per screen in the section accent (.tint).
struct ResultRow: View {
    let label: String
    let value: String
    var unit: String = ""
    var emphasis: Bool = false
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(OTL.textSecondary)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(emphasis
                          ? .system(.title2, design: .monospaced).weight(.semibold)
                          : .system(.callout, design: .monospaced).weight(.medium))
                    .foregroundStyle(emphasis ? AnyShapeStyle(.tint)
                                              : AnyShapeStyle(OTL.textPrimary))
                if !unit.isEmpty {
                    Text(unit).font(.footnote).foregroundStyle(OTL.textTertiary)
                }
            }
            .monospacedDigit()
        }
        .font(.callout)
    }
}
