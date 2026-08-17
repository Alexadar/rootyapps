import SwiftUI

#if canImport(RealityKit)
import RealityKit
#endif

/// Froggo 1's palette, carried over exactly. PROMPT.md §6a: do not invent a new one.
///
/// Every colour below is either measured from froggo 1's shipped assets or derived from those
/// measurements — and where it is derived, the reason is written down. The point is that Froggo 2
/// should be recognisably the same game rendered with depth, not a new game wearing its name.
enum Palette {
    // MARK: - Measured from froggo 1

    /// Apple systemGreen (dark). 37% of the idle sprite, 67% of the jump sprite — the frog's colour.
    static let frogBody = Color(hex: 0x30D158)
    /// Apple systemGreen. The frog's second tone.
    static let frogAccent = Color(hex: 0x34C759)
    /// Eyes, belly, highlights.
    static let frogHighlight = Color(hex: 0xFFFFFF)
    /// The palette's only dark: outline accent, 1% of the sprite.
    static let frogOutline = Color(hex: 0x1A0D0D)

    /// systemOrange — the lit windows in `scraper.png`, 69% of it.
    static let windowLit = Color(hex: 0xFFA90A)
    /// systemBlue — the facade behind the windows, 28%.
    static let facade = Color(hex: 0x0A84FF)

    /// The sky, 87% of `NightSky.png`.
    static let sky = Color(hex: 0x0A84FF)
    /// Cloud/haze greys from the sky texture.
    static let haze = Color(hex: 0xACACAC)
    static let hazeLight = Color(hex: 0xFFFFFF)
    /// The sky's accent.
    static let skyAccent = Color(hex: 0x64D2FF)

    // MARK: - Derived, with the derivation stated

    /// Rooftop top face: the facade blue at 0.65 luminance.
    ///
    /// Derived because froggo 1 had no roofs — a side-on 2-D building has no top surface. A roof
    /// that reads as distinct from the facade is what makes the landing pad legible from a
    /// third-person camera, and legibility of the pad is most of what makes a 3-D gap judgeable.
    static let roof = Color(hex: 0x0A84FF).darkened(0.35)

    /// The aim arc: froggo 1's exact `trajectoryLine` stroke — white at 0.7 alpha (Frog.swift:79-81).
    static let arc = Color.white.opacity(0.7)

    /// Landing ring when the target is reachable at the current power.
    static let ringReachable = frogBody
    /// Landing ring when it is not.
    ///
    /// Deliberately `windowLit`, not red: orange is already in the palette as the lit-window colour,
    /// so out-of-range reads as "not yet" rather than as an error state, and no new hue enters the
    /// game. PROMPT.md §6a asks for derivation rather than invention, and this is the derivation.
    static let ringUnreachable = windowLit

    /// Haze at the base of the towers, fading upward — the palette's only dark, used to sell height.
    static let towerBaseHaze = frogOutline
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    func darkened(_ amount: Double) -> Color {
        let f = max(0, 1 - amount)
        #if canImport(UIKit)
        let native = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        native.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(.sRGB, red: Double(r) * f, green: Double(g) * f, blue: Double(b) * f, opacity: Double(a))
        #else
        let native = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return Color(.sRGB,
                     red: Double(native.redComponent) * f,
                     green: Double(native.greenComponent) * f,
                     blue: Double(native.blueComponent) * f,
                     opacity: Double(native.alphaComponent))
        #endif
    }
}
