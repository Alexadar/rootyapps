import SwiftUI

// MARK: - Glass card

extension View {
    /// Nebula glass card — replaces the light `.glassEffect` look on dark space.
    /// Translucent white fill + soft violet border + purple drop-glow.
    func nebulaCard(cornerRadius: CGFloat = 20, dense: Bool = false) -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)                         // frosts what's behind
                    .opacity(0.54)                                    // …sheerer still, so the sky reads through the glass
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(dense ? NebulaPalette.cardFillAlt : NebulaPalette.cardFill)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(NebulaPalette.cardBorder, lineWidth: 0.75)
            )
            .shadow(color: Color(rgbHex: 0x7828C8).opacity(0.5), radius: 22, x: 0, y: 12)
            .foregroundStyle(NebulaPalette.textPrimary)
    }

    /// Soft luminous glow for planet glyphs and hero titles.
    func nebulaGlow(_ color: Color = Color(rgbHex: 0xA078FF), radius: CGFloat = 6) -> some View {
        self.shadow(color: color.opacity(0.9), radius: radius)
    }
}

// MARK: - Header (matches CardHeader, restyled)

struct NebulaCardHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(NebulaPalette.textHead)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NebulaPalette.accent)
            }
        }
    }
}

// MARK: - Zodiac sign chip

/// Solid violet chip with a white sign glyph — used in Positions, the wheel, and Cycle.
struct SignChip: View {
    let glyph: String
    var size: CGFloat = 22
    var body: some View {
        Text(glyph)
            .font(.system(size: size * 0.6))
            .foregroundStyle(NebulaPalette.signGlyph)
            .frame(width: size, height: size)
            .background(NebulaPalette.sign, in: .rect(cornerRadius: size * 0.27))
    }
}
