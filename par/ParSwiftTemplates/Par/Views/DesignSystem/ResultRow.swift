import SwiftUI

/// A secondary result — one of the several a Kit returns alongside the hero.
public struct ResultRow: View {
    public enum Emphasis { case normal, strong }

    private let label: String
    private let value: String
    private let unit: String?
    private let emphasis: Emphasis
    private let identifier: String
    private let spoken: String?

    public init(
        _ label: String,
        value: String,
        unit: String? = nil,
        emphasis: Emphasis = .normal,
        identifier: String,
        spoken: String? = nil
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.emphasis = emphasis
        self.identifier = identifier
        self.spoken = spoken
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Par.Palette.labelSecondary)
            Spacer(minLength: 10)
            Text(value)
                .font(emphasis == .strong ? .headline.monospacedDigit() : .subheadline.monospacedDigit())
                .foregroundStyle(Par.Palette.label)
            if let unit {
                Text(unit).font(.caption).foregroundStyle(Par.Palette.labelSecondary)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .glassCard(radius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(spoken ?? "\(label), \(value)")
    }
}
