import SwiftUI

/// Labeled numeric input row — value shown in a monospaced chip (decimal pad on iOS).
/// `range` clamps the committed value to the field's valid mathematical domain.
///
/// `title` is a `LocalizedStringKey` (the literal at the call site becomes the catalog key);
/// `unit` stays a `String` — Hz, dB and m³ are the same in every language the app ships.
/// The field parses with `.number`, which resolves against the environment locale, so a German
/// user types `0,17` and `Fmt` prints `0,17` back. See `LanguageStore`.
struct NumberField: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    var unit: String = ""
    var range: ClosedRange<Double>? = nil
    /// Names this field for Audio Analysis. When set, a measured value shows its three provenance
    /// signals here and typing clears them — there is no "measured but modified".
    var field: FieldKey? = nil

    @EnvironmentObject private var provenance: FieldProvenance

    private var bound: Binding<Double> {
        Binding(get: { value },
                set: { v in
                    // The user typed: provenance goes immediately, before the value even lands, so
                    // there is no frame in which a changed number still claims to be measured.
                    if let field, provenance.isMeasured(field) { provenance.markTyped(field) }
                    value = range.map { Swift.min(Swift.max(v, $0.lowerBound), $0.upperBound) } ?? v
                })
    }

    var body: some View {
        if let field, provenance.isMeasured(field) {
            MeasuredValue(provenance: provenance.provenance(for: field),
                          label: title,
                          spokenValue: Fmt.f(value, 2)) {
                row
            }
            .accessibilityAction(named: Text("Revert to typed")) {
                if let previous = provenance.revert(field) { value = previous }
            }
        } else {
            row
        }
    }

    private var row: some View {
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
///
/// `id` names the VALUE leaf, never this row: an identifier on a container overwrites its children's,
/// so putting it here would make the label and the value both answer to the same name and neither
/// addressable — for a test or for VoiceOver. Purely additive; nothing about it is visible.
struct ResultRow: View {
    let label: LocalizedStringKey
    let value: String
    var unit: String = ""
    var emphasis: Bool = false
    var id: String? = nil
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
                    .accessibilityIdentifier(id ?? "")
                if !unit.isEmpty {
                    Text(unit).font(.footnote).foregroundStyle(OTL.textTertiary)
                }
            }
            .monospacedDigit()
        }
        .font(.callout)
    }
}
