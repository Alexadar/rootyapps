import SwiftUI
import EphemerisKit

/// Stage 2 — planetary positions from the ephemeris.
struct PositionsTable: View {
    let positions: [BodyPosition]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Positions")
            ForEach(positions) { p in
                HStack(spacing: 10) {
                    Text(p.body.glyph + "\u{FE0E}").font(.title3)
                        .foregroundStyle(NebulaPalette.glyph).nebulaGlow().frame(width: 26)
                    Text(p.body.name).frame(width: 78, alignment: .leading)
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

    private func motion(_ p: BodyPosition) -> String {
        (p.retrograde ? "℞ " : "") + String(format: "%.2f°/d", p.speed)
    }
}
