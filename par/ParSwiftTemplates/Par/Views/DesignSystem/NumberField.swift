import SwiftUI

/// A bounded numeric input. The Kit guards illegal domains by trapping or throwing;
/// this field's job is to make an illegal value un-enterable, so `range` is required.
public struct NumberField: View {
    private let symbol: String
    private let caption: String
    private let unit: String?
    private let range: ClosedRange<Double>
    private let digits: Int
    private let isSolveTarget: Bool
    @Binding private var value: Double
    private let identifier: String

    @FocusState private var focused: Bool
    @State private var text: String = ""

    public init(
        _ symbol: String,
        caption: String,
        unit: String? = nil,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        digits: Int = 2,
        isSolveTarget: Bool = false,
        identifier: String
    ) {
        self.symbol = symbol
        self.caption = caption
        self.unit = unit
        self._value = value
        self.range = range
        self.digits = digits
        self.isSolveTarget = isSolveTarget
        self.identifier = identifier
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(symbol)
                    .font(.headline)
                    .foregroundStyle(isSolveTarget ? Par.Palette.accent : Par.Palette.label)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(isSolveTarget ? Par.Palette.accent : Par.Palette.labelSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if isSolveTarget {
                Text("—")
                    .font(.title3)
                    .foregroundStyle(Par.Palette.labelQuaternary)
            } else {
                TextField("", text: $text)
                    .multilineTextAlignment(.trailing)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(Par.Palette.label)
                    .focused($focused)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .onAppear { text = Fmt.money(value, digits: digits) }
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commit() } else { text = trimmedEntry }
                    }
                    .accessibilityIdentifier(identifier)
                    .accessibilityLabel(caption)
                    .accessibilityValue(Fmt.money(value, digits: digits))
            }

            if let unit {
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Par.Palette.labelSecondary)
                    .frame(minWidth: 52, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: Par.Metrics.minHitTarget)
        .background(isSolveTarget || focused ? Par.Palette.accentTint : .clear)
        .overlay(alignment: .leading) {
            if focused { Rectangle().fill(Par.Palette.accent).frame(width: 2.5) }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private var trimmedEntry: String {
        value == 0 ? "" : String(value)
    }

    /// Clamping is the whole point: the Kit must never receive an illegal domain.
    private func commit() {
        let parsed = Double(text.replacingOccurrences(of: ",", with: "")) ?? value
        value = min(max(parsed, range.lowerBound), range.upperBound)
        text = Fmt.money(value, digits: digits)
    }
}
