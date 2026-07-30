import SwiftUI
import DimensionKit

private func trim(_ x: Double) -> String {
    if abs(x - x.rounded()) < 1e-9 { return String(Int(x.rounded())) }
    return String(format: "%.4f", x)
}

// MARK: Units converter
struct UnitsToolView: View {
    @State private var value = 1.0
    @State private var from: LengthUnit = .foot
    @State private var to: LengthUnit = .meter

    var body: some View {
        ToolColumns {
            VStack(spacing: 12) {
                CardHeader(title: "Convert")
                NumberField(title: "Value", value: $value, range: -1_000_000...1_000_000)
                HStack {
                    Text("From").foregroundStyle(KC.textPrimary)
                    Spacer()
                    unitMenu($from)
                }
                HStack {
                    Text("To").foregroundStyle(KC.textPrimary)
                    Spacer()
                    unitMenu($to)
                }
                Button {
                    let t = from; from = to; to = t
                } label: {
                    Label("Swap", systemImage: "arrow.up.arrow.down")
                        .font(.footnote.weight(.semibold))
                }.buttonStyle(.plain).foregroundStyle(.tint)
            }.card()
        } outputs: {
            HeroReadout(label: "\(trim(value)) \(from.symbol) =", value: trim(result), unit: to.symbol, identifier: "units.hero")

            VStack(spacing: 10) {
                CardHeader(title: "All units")
                ForEach(LengthUnit.allCases) { u in
                    ResultRow(label: u.rawValue.capitalized,
                              value: trim(Units.convert(value, from: from, to: u)), unit: u.symbol)
                }
            }.card()
        }
    }
    private var result: Double { Units.convert(value, from: from, to: to) }

    private func unitMenu(_ sel: Binding<LengthUnit>) -> some View {
        Menu {
            ForEach(LengthUnit.allCases) { u in
                Button(u.rawValue.capitalized) { sel.wrappedValue = u }
            }
        } label: {
            Text(sel.wrappedValue.rawValue.capitalized)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(KC.chipFill, in: .rect(cornerRadius: KC.rChip))
                .foregroundStyle(.tint)
        }
    }
}
