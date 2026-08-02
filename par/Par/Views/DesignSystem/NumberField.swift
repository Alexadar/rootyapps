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
    /// True when a keypad is the entry method. The text field then displays but does not edit, so a
    /// tap selects the row for the keypad instead of raising the system keyboard over the app.
    private let isKeypadDriven: Bool
    /// The keystrokes typed into this register so far, when it is the keypad's target. Non-nil means
    /// an entry is in progress and it, not `value`, is what the user is looking at.
    private let pendingEntry: String?
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
        isKeypadDriven: Bool = false,
        pendingEntry: String? = nil,
        identifier: String
    ) {
        self.symbol = symbol
        self.caption = caption
        self.unit = unit
        self._value = value
        self.range = range
        self.digits = digits
        self.isSolveTarget = isSolveTarget
        self.isKeypadDriven = isKeypadDriven
        self.pendingEntry = pendingEntry
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
            } else if isKeypadDriven {
                let shown = pendingEntry.map { $0.isEmpty ? "0" : $0 }
                    ?? Fmt.money(value, digits: digits)
                // Display only: the keypad is the entry method, so there is one source of truth for
                // this number and it is the binding.
                Text(shown)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(Par.Palette.label)
                    .accessibilityIdentifier(identifier)
                    .accessibilityLabel(caption)
                    .accessibilityValue(shown)
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
                    .onChange(of: value) { _, newValue in
                        if !focused { text = Fmt.money(newValue, digits: digits) }
                    }
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
        // The gesture is attached ONLY when this field owns its entry. An `onTapGesture` whose
        // closure does nothing still consumes the tap, which is what stopped the enclosing row from
        // ever being selected for the keypad.
        .modifier(TapToFocus(enabled: !isKeypadDriven, focused: $focused))
    }

    /// Attaches the focus tap only when the field is its own entry method.
    private struct TapToFocus: ViewModifier {
        let enabled: Bool
        @FocusState.Binding var focused: Bool

        func body(content: Content) -> some View {
            if enabled {
                content.onTapGesture { focused = true }
            } else {
                content
            }
        }
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
