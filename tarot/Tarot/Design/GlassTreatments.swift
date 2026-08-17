import SwiftUI

/// THE one legal home of `.glassEffect` in this app (the aisixteen discipline, enforced by
/// `GlassDisciplineChecks`): a design with even one bare call site elsewhere ships a screen
/// that ignores Reduce Transparency. Chrome takes its glass from here; **cards never do** —
/// cards are lit 3D objects and must read as physical.
extension View {
    /// The standard chrome panel: dark-tinted regular glass in a rounded rectangle.
    func tarotGlassPanel(cornerRadius: CGFloat = 24) -> some View {
        glassEffect(.regular.tint(Tokens.glassTint.opacity(0.55)),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// A small capsule chip (hints, status lines).
    func tarotGlassChip() -> some View {
        glassEffect(.regular.tint(Tokens.glassTint.opacity(0.45)), in: Capsule())
    }
}
