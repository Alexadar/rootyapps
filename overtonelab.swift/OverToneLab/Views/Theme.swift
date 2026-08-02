import SwiftUI

extension View {
    /// A matte card: padded, filled surface, 1px hairline stroke (no glass).
    func glassCard(cornerRadius: CGFloat = OTL.rCard, raised: Bool = false) -> some View {
        self.padding(16)
            .background(raised ? OTL.surfaceRaised : OTL.surface,
                        in: .rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(OTL.hairline, lineWidth: 1)
            )
    }
}

/// Section header inside a card — monospaced, uppercased, tracked.
///
/// `title` is a `LocalizedStringKey` so the literal at the call site reaches Localizable.xcstrings;
/// `trailing` stays a `String` because it carries a formatted number, never prose. Uppercasing is
/// done with `.textCase(.uppercase)` rather than `String.uppercased()` so it follows the
/// environment locale — Turkish dotless ı is the case this protects.
struct CardHeader: View {
    let title: LocalizedStringKey
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title)
                .textCase(.uppercase)
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .tracking(1)
                .foregroundStyle(OTL.textSecondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.tint)   // set .tint(tool.accent) at the screen level
            }
        }
    }
}
