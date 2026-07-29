import SwiftUI

/// The one loud number on a screen.
///
/// No pinned point size anywhere: the numeral is `.largeTitle` scaled, so it
/// grows with Dynamic Type and WRAPS rather than truncates at the largest
/// accessibility sizes. Sign is carried by the glyph and by `direction`, not hue.
public struct HeroResult: View {
    private let caption: String
    private let value: String
    private let footnote: String
    private let identifier: String
    private let spoken: String

    public init(caption: String, value: String, footnote: String, identifier: String, spoken: String) {
        self.caption = caption
        self.value = value
        self.footnote = footnote
        self.identifier = identifier
        self.spoken = spoken
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Par.Palette.labelSecondary)
            Text(value)
                .font(.largeTitle.weight(.semibold).monospacedDigit())
                .foregroundStyle(Par.Palette.label)
                .lineLimit(nil)
                .minimumScaleFactor(1.0)          // wrap, never shrink-to-illegible
                .fixedSize(horizontal: false, vertical: true)
            Text(footnote)
                .font(.footnote)
                .foregroundStyle(Par.Palette.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(spoken)
    }
}
