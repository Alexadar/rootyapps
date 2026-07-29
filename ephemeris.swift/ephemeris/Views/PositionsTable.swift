import SwiftUI
import EphemerisKit

/// Stage 2 — planetary positions from the ephemeris.
struct PositionsTable: View {
    let positions: [BodyPosition]
    // The app's own locale, which the language override drives. `.formatted()` with no argument
    // would follow the *system* locale instead and print "0.52" to a user reading Ukrainian.
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Positions")
            ForEach(positions) { p in
                HStack(spacing: 10) {
                    Text(p.body.glyph + "\u{FE0E}").font(.title3)
                        .foregroundStyle(NebulaPalette.glyph).nebulaGlow().frame(width: 26)
                    Text(L.loc(p.body.name)).frame(width: 78, alignment: .leading)
                    SignChip(glyph: p.sign.glyph)
                    Text(p.degMinString).monospacedDigit()
                        .frame(width: 70, alignment: .leading)
                    Spacer()
                    Text(motion(p))
                        .font(.callout).monospacedDigit()
                        .foregroundStyle(p.retrograde ? NebulaPalette.retrograde : NebulaPalette.textSecondary)
                }
                .font(.callout)
                if p.id != positions.last?.id { NebulaPalette.divider.frame(height: 0.75) }
            }
        }
        .glassCard()
    }

    /// "℞ 0,52°/d" — the separator follows the chosen language; most of Europe writes a comma.
    private func motion(_ p: BodyPosition) -> String {
        let speed = p.speed.formatted(.number.precision(.fractionLength(2)).locale(locale))
        return (p.retrograde ? "℞ " : "") + speed + "°/d"
    }
}
