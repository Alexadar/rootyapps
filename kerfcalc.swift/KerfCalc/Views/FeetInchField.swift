import SwiftUI
import DimensionKit

/// A tool dimension field that reads/writes feet-inch. Drop-in for `NumberField` on LENGTH inputs.
/// Binds to the tool's existing `Double` (in `unit`); tapping opens the glove keypad (CM-Pro style),
/// which is driven by the same `CalcEngine`/`TapeCalc` as the Spec tab.
struct FeetInchField: View {
    let title: String
    @Binding var value: Double
    var unit: LengthUnit = .foot
    var range: ClosedRange<Double>? = nil
    /// Test handle, e.g. `input.rafter.run`. There are up to five of these on one screen and their
    /// titles repeat across tools ("Run", "Length"), so matching on the title is ambiguous.
    var identifier: String? = nil
    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            HStack {
                Text(title).foregroundStyle(KC.textPrimary)
                Spacer()
                Text(LengthEntry.text(value, unit: unit))
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(KC.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(KC.chipFill, in: .rect(cornerRadius: KC.rChip))
                Image(systemName: "square.grid.2x2").font(.footnote).foregroundStyle(.tint)
            }
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? "input")
        .sheet(isPresented: $editing) {
            FieldKeypadSheet(title: title,
                             initial: LengthEntry.feetInch(value, unit: unit)) { fi in
                var v = LengthEntry.value(fi, unit: unit)
                if let r = range { v = min(max(v, r.lowerBound), r.upperBound) }
                value = v
            }
            .presentationDetents([.height(540)])
            .presentationDragIndicator(.visible)
        }
    }
}

/// The keypad sheet — a graphite readout + a compact feet-inch keypad, on the shared engine.
private struct FieldKeypadSheet: View {
    let title: String
    let initial: FeetInch
    let onDone: (FeetInch) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = CalcEngine()
    @State private var seeded = false

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text(title.uppercased())
                    .font(.system(.caption, design: .monospaced).weight(.semibold)).tracking(1)
                    .foregroundStyle(KC.textSecondary)
                Spacer()
                Button("Done") { onDone(engine.currentValue); dismiss() }
                    .font(.headline).foregroundStyle(KC.textPrimary)
                    .accessibilityIdentifier("field.done")
            }
            Text(engine.display)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundStyle(KC.signal)
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                .accessibilityIdentifier("field.readout")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(18)
                .background(KC.instrument, in: .rect(cornerRadius: KC.rCard))
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.15), value: engine.display)

            FieldKeypad { handle($0) }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(AppBackground())
        .tint(KC.signal)
        .onAppear { if !seeded { engine.preload(initial); seeded = true } }
    }

    private func handle(_ k: FieldKeypad.Key) {
        switch k {
        case .digit(let n): engine.digit(n)
        case .feet: engine.feetKey()
        case .inch: engine.inchKey()
        case .frac: engine.fractionKey()
        case .back: engine.backspace()
        case .clear: engine.clear()
        case .done: onDone(engine.currentValue); dismiss()
        }
    }
}

/// Compact entry keypad (no operators / nav) — reuses `CalcKey` faces. 4 columns.
private struct FieldKeypad: View {
    enum Key: Hashable { case digit(Int), feet, inch, frac, back, clear, done }
    var tap: (Key) -> Void
    private let gap: CGFloat = 8

    var body: some View {
        VStack(spacing: gap) {
            row { d(7); d(8); d(9); k(.feet, "Feet", face: .dim) }
            row { d(4); d(5); d(6); k(.inch, "Inch", face: .dim) }
            row { d(1); d(2); d(3); k(.frac, "⁄",    face: .dim) }
            row {
                k(.clear, "C", face: .edit)
                d(0)
                k(.back, "⌫", face: .edit)
                k(.done, "=", face: .equals)
            }
        }
    }

    /// Prefixed `fkey.` — deliberately NOT `key.`, which the Spec keypad owns. The two pads share
    /// labels ("Feet", "⁄", "C", digits) and `=` means different things on each: evaluate on Spec,
    /// commit-and-dismiss here. Distinct namespaces keep a test from tapping the wrong pad's key.
    private func k(_ id: Key, _ label: String, face: KeyFace) -> some View {
        CalcKey(label: label, face: face, height: 56,
                identifier: "fkey." + FieldKeypad.name(id)) { tap(id) }
    }

    static func name(_ id: Key) -> String {
        switch id {
        case .digit(let n): return "digit\(n)"
        case .feet:  return "feet"
        case .inch:  return "inch"
        case .frac:  return "fraction"
        case .back:  return "backspace"
        case .clear: return "clear"
        case .done:  return "done"
        }
    }

    private func d(_ n: Int) -> some View { k(.digit(n), "\(n)", face: .digit) }
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: gap) { content() }
    }
}
