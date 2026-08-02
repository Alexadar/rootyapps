import SwiftUI

/// Par's visual language: amber on graphite, dark only.
///
/// One accent, spent only on interaction — the register you are in, the key that
/// solves, the primary button. Nothing else is coloured, so amber always means
/// "this is where you are, or this is what you press".
///
/// Sign is NOT carried by hue. On a graphite field, red beside amber reads as
/// mush, and a wrong-signed payment is too important to encode in a colour the
/// chrome also uses. Negatives carry by the minus glyph, by weight, and by the
/// spelled-out direction ("cash out") under the hero.
public enum Par {

    public enum Palette {
        /// App background.
        public static let base = Color(red: 0.075, green: 0.075, blue: 0.086)      // #131316
        /// Glass card fill over `base`.
        public static let surface = Color.white.opacity(0.06)
        /// Raised / pressed fill (keys, chips).
        public static let surfaceRaised = Color.white.opacity(0.16)
        /// Hairline top highlight that gives glass its edge.
        public static let surfaceHighlight = Color.white.opacity(0.13)
        public static let separator = Color.white.opacity(0.07)

        public static let accent = Color(red: 1.0, green: 0.624, blue: 0.039)      // #FF9F0A
        /// Ink to use on top of `accent`.
        public static let onAccent = Color(red: 0.075, green: 0.075, blue: 0.086)
        public static let accentTint = Color(red: 1.0, green: 0.624, blue: 0.039).opacity(0.12)

        public static let label = Color.white
        public static let labelSecondary = Color(white: 0.92).opacity(0.66)
        public static let labelTertiary = Color(white: 0.92).opacity(0.5)
        /// Empty register / unsolved slot.
        public static let labelQuaternary = Color(white: 0.92).opacity(0.28)

        public static let warning = Color(red: 1.0, green: 0.702, blue: 0.251)     // #FFB340
    }

    public enum Metrics {
        public static let cardRadius: CGFloat = 20
        public static let controlRadius: CGFloat = 12
        public static let keyRadius: CGFloat = 14
        /// Never below 44pt, per the brief: this app is used on a job site and in a car.
        public static let minHitTarget: CGFloat = 44
        public static let gutter: CGFloat = 16
    }
}

public extension View {
    /// The one card treatment in the app.
    func glassCard(radius: CGFloat = Par.Metrics.cardRadius) -> some View {
        self
            .background(Par.Palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Par.Palette.surfaceHighlight, lineWidth: 0.5)
            )
    }

    /// Par is dark-only. Applied once at the scene root; here for previews too.
    func parAppearance() -> some View {
        self.preferredColorScheme(.dark).tint(Par.Palette.accent)
    }
}
