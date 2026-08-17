import SwiftUI
import UnitsKit

/// An input field for one quantity.
///
/// ## Typing and stepping, both
///
/// A keyboard is the fast path at a desk and the wrong path in a crawlspace with gloves on, so the
/// field carries both: a text field for exact entry and a pair of 48-point stepper buttons for
/// nudging a value one-handed. The steppers are below the number, in the lower half of the screen,
/// where a thumb reaches.
///
/// ## The stored value never moves
///
/// The binding is SI. The text is a rendering of it, refreshed whenever the value or the unit
/// system changes from outside — but *not* while the field has focus, because rewriting the text
/// under someone's cursor eats the digit they were half-way through typing.
struct NumericField: View {

    let title: LocalizedStringKey
    let spokenTitle: String
    let quantity: Quantity
    let system: UnitSystem
    @Binding var siValue: Double
    /// Step size in display units.
    var step: Double = 1
    var isActive: Bool = false
    var identifier: String? = nil

    @State private var text: String = ""
    /// Which quantity the current `text` was rendered for.
    ///
    /// The psychrometrics screen changes a field's *quantity* under it — pick "wet bulb" where
    /// "relative humidity" was and the same field now means degrees. Without this, the old string
    /// survives the switch and the next `onChange` parses it under the new unit: 50 % becomes
    /// 1697, which is read as 1697 °F, which is out of range, and the screen stops solving. The
    /// iPad UI suite caught exactly that.
    @State private var textQuantity: Quantity?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            Text(title)
                .font(DS.ui(11.5, .semibold))
                .foregroundStyle(isActive ? DS.water : DS.ink2)

            HStack(alignment: .firstTextBaseline, spacing: DS.s1) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(DS.number(25))
                    .foregroundStyle(DS.ink)
                    .monospacedDigit()
                    .focused($focused)
                    .multilineTextAlignment(.leading)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    #endif
                    .onChange(of: text) { _, new in
                        // Only trust text that was rendered for the unit it is about to be read
                        // in. Anything else is a leftover from the previous quantity.
                        guard textQuantity == quantity else { return }

                        // **Ignore our own echo.** `refresh()` writes the *rounded display* of the
                        // stored value into `text`, and this handler used to parse that straight
                        // back into `siValue` — so every unit switch quantised the stored number to
                        // whatever the screen happened to show. Measured: an air-side load of
                        // 26,507 Btu/h became 26,607 after IP → SI → IP, and would keep moving.
                        //
                        // The app's promise is that switching units is free and reversible, so a
                        // change that merely re-states the current value must not be written back.
                        // Comparing against the current rendering does that with no flag to get
                        // out of sync: only text the *user* changed differs from it.
                        guard new != Fmt.value(si: siValue, quantity, system),
                              let parsed = Fmt.parse(new, quantity, system) else { return }
                        siValue = parsed
                    }
                    .accessibilityLabel(spokenTitle)
                    .accessibilityValue(Fmt.spoken(si: siValue, quantity, system))
                    .modifier(OptionalIdentifier(identifier: identifier))

                Text(quantity.symbol(system))
                    .font(DS.number(13, .medium))
                    .foregroundStyle(DS.ink2)
            }

            HStack(spacing: DS.s2) {
                stepButton("minus", delta: -step)
                stepButton("plus", delta: step)
            }
        }
        .padding(.horizontal, DS.s3)
        .padding(.vertical, DS.s2 + 2)
        // The width below which this field stops being readable — a four-digit flow plus its unit
        // and two steppers. It exists so `ViewThatFits` can do its job: without a minimum, a row of
        // three fields always "fits" by squeezing, and 7,500 CFM shipped as "7,5…". A container
        // that cannot refuse cannot be chosen against.
        .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
        .background(DS.card)
        .overlay(RoundedRectangle(cornerRadius: DS.radiusCard)
            .stroke(isActive ? DS.water : DS.border, lineWidth: isActive ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: DS.radiusCard))
        .onAppear { refresh() }
        .onChange(of: siValue) { _, _ in if !focused { refresh() } }
        .onChange(of: system) { _, _ in refresh() }
        .onChange(of: quantity) { _, _ in refresh() }
        .onChange(of: focused) { _, isFocused in if !isFocused { refresh() } }
    }

    private func refresh() {
        textQuantity = quantity
        text = Fmt.value(si: siValue, quantity, system)
    }

    private func stepButton(_ symbol: String, delta: Double) -> some View {
        Button {
            let current = quantity.display(si: siValue, in: system)
            siValue = quantity.si(display: current + delta, in: system)
            refresh()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.water)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(DS.waterTint)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(DS.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: DS.hitTarget - 16)
        .accessibilityLabel(delta > 0 ? "Increase \(spokenTitle)" : "Decrease \(spokenTitle)")
    }
}

/// `accessibilityIdentifier` takes a non-optional, and a UI test needs a stable handle only on the
/// fields it drives — so the modifier is applied conditionally rather than inventing identifiers
/// for every field in the app.
private struct OptionalIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
