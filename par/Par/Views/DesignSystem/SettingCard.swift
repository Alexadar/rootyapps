import SwiftUI

/// A card that looks like `ResultRow` but is a control.
///
/// This exists because of a specific defect: P/YR, C/YR, BEG/END on the TVM screen, the payment
/// frequency on Amortization, and the coupon frequency on Day Count were all rendered as
/// display-only `ResultRow`s bound to properties nothing in the app ever assigned. Every Kit
/// supported every value; the screens simply had no way to set them, so an annuity-due and a
/// quarterly instrument were unreachable in a financial calculator.
///
/// The chevron is the whole point. A card that can be changed must not look identical to one that
/// cannot, or the app is lying about what it offers.
public struct SettingCard<Menu: View>: View {
    private let label: String
    private let value: String
    private let identifier: String
    private let spoken: String?
    @ViewBuilder private let menu: () -> Menu

    public init(_ label: String, value: String, identifier: String, spoken: String? = nil,
                @ViewBuilder menu: @escaping () -> Menu) {
        self.label = label
        self.value = value
        self.identifier = identifier
        self.spoken = spoken
        self.menu = menu
    }

    public var body: some View {
        SwiftUI.Menu {
            menu()
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Par.Palette.labelSecondary)
                Spacer(minLength: 10)
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Par.Palette.label)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Par.Palette.labelTertiary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .glassCard(radius: 16)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(spoken ?? "\(label), \(value)")
    }
}

/// The frequencies instruments are actually written at, named rather than merely numbered — "26" is
/// biweekly to a lender and noise to everyone else.
public enum Frequency {
    public static let all: [(count: Int, name: String)] = [
        (1, "annual"), (2, "semiannual"), (4, "quarterly"),
        (12, "monthly"), (26, "biweekly"), (52, "weekly"),
    ]

    public static func name(for count: Int) -> String {
        all.first { $0.count == count }?.name ?? "\(count) per year"
    }

    /// An inline picker over `all`, for use as a `SettingCard`'s menu.
    @ViewBuilder
    public static func picker(_ label: String, selection: Binding<Int>) -> some View {
        Picker(label, selection: selection) {
            ForEach(all, id: \.count) { frequency in
                Text("\(frequency.count) · \(frequency.name)").tag(frequency.count)
            }
        }
        .pickerStyle(.inline)
    }
}
