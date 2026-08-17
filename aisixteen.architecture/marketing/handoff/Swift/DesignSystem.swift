import SwiftUI

// AISixteen Architecture — design tokens.
// Shared DNA with AISixteen Wallpapers; deltas: terracotta accent, bottom sheet, preset card.
enum DS {
    static let ink = Color(red: 0x1D/255, green: 0x1A/255, blue: 0x17/255)
    static let accent = Color(red: 0xB4/255, green: 0x55/255, blue: 0x2D/255) // terracotta
    static let canvas = Color(red: 0xEF/255, green: 0xEB/255, blue: 0xE4/255)
    static let canvasAlt = Color(red: 0xF4/255, green: 0xF1/255, blue: 0xEB/255)
    static let good = Color(red: 0x3E/255, green: 0x8E/255, blue: 0x5A/255)

    static let rCard: CGFloat = 26
    static let rSheet: CGFloat = 34
    static let rPreset: CGFloat = 18

    static let morph = Animation.spring(response: 0.8, dampingFraction: 0.85)
}

// Standing control surface over a full-bleed photo (delta vs wallpaper app).
struct GlassSheet<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity)
            .glassEffect(in: .rect(topLeadingRadius: DS.rSheet, topTrailingRadius: DS.rSheet))
    }
}

struct StylePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let sub: String
    let swatches: [Color]
    let prompt: String

    static let interior: [StylePreset] = [
        .init(id: "scandi", name: "Scandinavian", sub: "Pale oak, white, calm",
              swatches: [Color(hex: 0xEFEAE2), Color(hex: 0xD8C6A6), Color(hex: 0xC7CBC6), Color(hex: 0x5E7357)],
              prompt: "Bright Scandinavian living room, pale oak floor, white walls, wool textiles"),
        .init(id: "midcentury", name: "Mid-century", sub: "Walnut, brass, olive",
              swatches: [Color(hex: 0x8A5A34), Color(hex: 0xC98F4B), Color(hex: 0x3F5044), Color(hex: 0xE4D6BC)],
              prompt: "Mid-century modern living room, walnut furniture, brass accents, olive tones"),
        .init(id: "industrial", name: "Industrial", sub: "Concrete, steel, leather",
              swatches: [Color(hex: 0x4A4A4C), Color(hex: 0x8C8C8E), Color(hex: 0x5C4632), Color(hex: 0xB7B3AC)],
              prompt: "Industrial loft interior, concrete walls, steel fixtures, leather seating"),
        .init(id: "japandi", name: "Japandi", sub: "Low, warm, unadorned",
              swatches: [Color(hex: 0xE9E2D4), Color(hex: 0xB8A88C), Color(hex: 0x6B6A5E), Color(hex: 0x2E2C27)],
              prompt: "Japandi interior, low wooden furniture, warm neutral palette, uncluttered"),
    ]
    static let exterior: [StylePreset] = [
        .init(id: "farmhouse", name: "Modern farmhouse", sub: "Board & batten, black trim",
              swatches: [Color(hex: 0xE8E4DA), Color(hex: 0x2E2C27), Color(hex: 0x8FA98F), Color(hex: 0xB99B78)],
              prompt: "Modern farmhouse facade, white board and batten siding, black window trim"),
        .init(id: "mediterranean", name: "Mediterranean", sub: "Stucco, terracotta, arches",
              swatches: [Color(hex: 0xF0E6D4), Color(hex: 0xB4552D), Color(hex: 0x7E9694), Color(hex: 0x5C4632)],
              prompt: "Mediterranean house facade, warm stucco, terracotta roof tiles, arched windows"),
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF)/255,
                  green: Double((hex >> 8) & 0xFF)/255,
                  blue: Double(hex & 0xFF)/255)
    }
}
