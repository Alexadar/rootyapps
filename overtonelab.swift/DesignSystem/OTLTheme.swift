import SwiftUI

// Replaces Theme.swift + AppBackground.swift. Keeps every call site: `something.glassCard()`.

extension View {
    /// Matte "studio" card — replaces the old .glassEffect card.
    /// - Parameter raised: use the slightly lighter readout surface for the result card.
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

/// Small monospaced, uppercased section label inside a card.
struct CardHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title.uppercased())
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

/// Flat studio background — replaces the violet gradient + radial glow.
/// Pass the current tool's accent for a faint top glow on a detail screen.
struct AppBackground: View {
    var accent: Color? = nil
    var body: some View {
        OTL.background
            .overlay(alignment: .top) {
                if let accent {
                    RadialGradient(colors: [accent.opacity(0.10), .clear],
                                   center: .top, startRadius: 0, endRadius: 420)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
    }
}
