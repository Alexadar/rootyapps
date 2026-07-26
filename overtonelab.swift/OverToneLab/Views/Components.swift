import SwiftUI

/// Labeled numeric input row — value shown in a monospaced chip (decimal pad on iOS).
/// `range` clamps the committed value to the field's valid mathematical domain.
struct NumberField: View {
    let title: String
    @Binding var value: Double
    var unit: String = ""
    var range: ClosedRange<Double>? = nil

    private var bound: Binding<Double> {
        Binding(get: { value },
                set: { v in value = range.map { Swift.min(Swift.max(v, $0.lowerBound), $0.upperBound) } ?? v })
    }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(OTL.textPrimary)
            Spacer()
            TextField(title, value: bound, format: .number)
                .multilineTextAlignment(.trailing)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .frame(minWidth: 44)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(OTL.chipFill, in: .rect(cornerRadius: OTL.rChip))
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .textFieldStyle(.plain)
            if !unit.isEmpty {
                Text(unit).font(.footnote)
                    .foregroundStyle(OTL.textTertiary)
                    .frame(width: 40, alignment: .leading)
            }
        }
        .font(.callout)
    }
}

/// Read-only result row: label left, monospaced value right. `emphasis` = the one hero readout.
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
