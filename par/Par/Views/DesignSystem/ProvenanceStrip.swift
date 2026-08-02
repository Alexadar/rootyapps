import SwiftUI

/// The authority a screen implements, and the conventions in force.
///
/// This is furniture, not fine print — it is the product's whole claim made
/// visible, so it is never below `.caption2` and never below AA contrast.
public struct ProvenanceStrip: View {
    private let authorities: [String]
    private let conventions: [String]
    private let identifier: String

    public init(authorities: [String], conventions: [String], identifier: String) {
        self.authorities = authorities
        self.conventions = conventions
        self.identifier = identifier
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(Par.Palette.labelSecondary)
                .accessibilityHidden(true)
            Text(line)
                .font(.caption2.monospaced())
                .foregroundStyle(Par.Palette.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Par.Palette.surface, in: RoundedRectangle(cornerRadius: Par.Metrics.stripRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel("Sources and conventions. " + line)
    }

    private var line: String {
        (authorities + conventions).joined(separator: " · ")
    }
}
