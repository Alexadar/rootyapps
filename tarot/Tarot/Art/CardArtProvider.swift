import CoreGraphics
import Foundation
import TarotKit

/// Everything the renderer needs to dress one card.
struct CardArt {
    /// The face illustration.
    let face: CGImage
    /// The foil mask: R = foil region strength, G = film-thickness variation (drives the
    /// thin-film hue for majors), B = fine relief (breaks the streak like etched foil).
    let foilMask: CGImage
    /// Foil tier: minors get border foil, majors the full thin-film treatment.
    let isMajor: Bool
}

/// The seam real art drops through. The card layer sees only this protocol — swapping the
/// procedural placeholder for generated art is a new conformer, zero renderer changes.
/// (Same mock-seam discipline as notescan's MagicService and froggo2's FrogRig.)
@MainActor
protocol CardArtProvider {
    /// The face of one card AS THIS DECK NAMES IT — the same structural card renders
    /// "Page of Wands", "Valet of Wands" or (a major) a different name entirely per deck.
    /// Generated/loaded lazily — only drawn cards ever need faces.
    func art(for card: Card, deck: Deck) -> CardArt
    /// The shared card back (one texture for the whole deck).
    func backArt() -> CardArt
}
