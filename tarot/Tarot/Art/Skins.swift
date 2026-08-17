import CoreGraphics
import Foundation
import TarotKit

/// The three abstractions of the game, named (owner, 2026-08-17):
///
///   METHOD — how cards are laid and read. Lives in TarotKit as `Spread` (`Method` is its
///            public alias there): positions, their meanings, the prompt framing.
///   DECK   — which 78 cards exist, their names and order. TarotKit's `Deck`, pure data.
///   SKIN   — how a deck LOOKS: colors, lattice, borders, typography, foil. A deck can
///            change skins freely; a skin knows nothing about which deck it dresses.
///
/// Skins are the unit of future sale (business compass: games may sell one-time unlocks),
/// so a new skin must be data — a `SkinSpec` — never new drawing code. `SkinnedArtProvider`
/// is the single interpreter of specs; everything it draws is original procedural work
/// (no scanned imagery of any historical deck is bundled, and none may ever be).
protocol CardSkin: Sendable {
    var id: String { get }
    var displayName: String { get }
    var spec: SkinSpec { get }
}

/// Everything a face/back render is allowed to vary. Colors are CGColor components in
/// device RGB; geometry in canvas points (512 × 880).
struct SkinSpec: Sendable {
    struct RGBA: Sendable {
        var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
        var cg: CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
        func alpha(_ value: CGFloat) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: value) }
    }

    // Faces — background + text, no pictures (owner, 2026-08-17).
    var faceBackground: RGBA
    var faceInk: RGBA               // name text on minors
    var majorAccent: RGBA           // gold family: numeral, border, name on majors
    var wandsAccent: RGBA
    var cupsAccent: RGBA
    var swordsAccent: RGBA
    var pentaclesAccent: RGBA
    var faceLatticeAlpha: CGFloat   // the faint diagonal weave behind the text
    var faceLatticeSpacing: CGFloat

    // Back — must read as "not a face" at a glance.
    var backBackground: RGBA
    var backAccent: RGBA
    var backLatticeSpacing: CGFloat
    var backEmblem: String          // a glyph, drawn as text

    func accent(for suit: Suit) -> RGBA {
        switch suit {
        case .wands: wandsAccent
        case .cups: cupsAccent
        case .swords: swordsAccent
        case .pentacles: pentaclesAccent
        }
    }
}

/// The default skin: the midnight-and-gold style of the deck back, extended to the faces.
struct MidnightSkin: CardSkin {
    let id = "midnight"
    let displayName = "Midnight"

    let spec = SkinSpec(
        faceBackground: .init(r: 0.10, g: 0.09, b: 0.17, a: 1),
        faceInk: .init(r: 0.92, g: 0.88, b: 0.78, a: 1),
        majorAccent: .init(r: 0.88, g: 0.72, b: 0.35, a: 1),
        wandsAccent: .init(r: 0.86, g: 0.56, b: 0.30, a: 1),
        cupsAccent: .init(r: 0.56, g: 0.70, b: 0.90, a: 1),
        swordsAccent: .init(r: 0.76, g: 0.79, b: 0.88, a: 1),
        pentaclesAccent: .init(r: 0.80, g: 0.76, b: 0.38, a: 1),
        faceLatticeAlpha: 0.10,
        faceLatticeSpacing: 88,
        backBackground: .init(r: 0.07, g: 0.07, b: 0.16, a: 1),
        backAccent: .init(r: 0.72, g: 0.60, b: 0.32, a: 1),
        backLatticeSpacing: 64,
        backEmblem: "✶")
}

enum Skins {
    /// Every skin the app knows. Selling one later = shipping its spec plus an unlock
    /// gate here; the render path is already done.
    static let all: [any CardSkin] = [MidnightSkin()]
    static let standard: any CardSkin = MidnightSkin()
}
