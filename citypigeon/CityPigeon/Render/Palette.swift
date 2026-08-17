import Foundation
import simd

/// Froggo 1's palette, measured from its shipped PNGs, carried over and extended to daylight.
///
/// PROMPT §4: **do not invent a palette.** Every colour below is either one of the measured hexes or
/// derived from them with the derivation stated. City Pigeon is set in the same city as Froggo, so
/// it should look like the same city — seen by day, from a bird.
///
/// The daylight decision costs exactly one thing: `NightSky.png` cannot carry over. That is the only
/// asset replaced, and its replacement is built from two colours already in the palette.
enum Palette {

    // MARK: - Measured from froggo 1

    /// systemOrange — the lit windows in `scraper.png`, 69% of it.
    static let windowLit = rgb(0xFFA90A)
    /// systemBlue — the facade behind the windows, 28%.
    static let facade = rgb(0x0A84FF)
    /// The sky's accent in `NightSky.png`.
    static let skyAccent = rgb(0x64D2FF)
    /// Cloud and haze greys.
    static let haze = rgb(0xACACAC)
    static let hazeLight = rgb(0xFFFFFF)
    /// The palette's only dark.
    static let outline = rgb(0x1A0D0D)
    /// The Froggo greens, which survive here as vehicle paint.
    static let green = rgb(0x30D158)
    static let greenAlt = rgb(0x34C759)
    static let white = rgb(0xFFFFFF)

    // MARK: - Derived, with the derivation stated

    /// Sky, top of frame. **Derived:** the existing `skyAccent`, unchanged — froggo's night sky
    /// already contained the blue a daytime sky wants, as its accent rather than its body.
    static let skyTop = skyAccent
    /// Sky, horizon. **Derived:** `hazeLight`, the cloud colour from the same texture. A vertical
    /// ramp between two colours already in the palette replaces the night texture outright.
    static let skyHorizon = hazeLight

    /// Asphalt. **Derived:** `haze` darkened 55%. Froggo 1 had no street — it was a game about
    /// rooftops — so this is the one surface with no ancestor. Deriving it from the haze grey keeps
    /// it in family and, more usefully, keeps it a *neutral* against which the palette's saturated
    /// vehicle colours read clearly. That legibility is the whole reason for choosing daylight.
    static let asphalt = haze * 0.45
    /// Lane markings. **Derived:** `hazeLight` at three-quarters, so they read without glaring.
    static let laneMark = hazeLight * 0.92
    /// Pavement. **Derived:** `haze` darkened 20% — lighter than the road, as pavement is.
    static let pavement = haze * 0.62
    /// Kerb edge. **Derived:** `haze` darkened 35%, between road and pavement.
    static let kerb = haze * 0.65

    /// The pigeon, **built entirely from existing hexes and no new hue**.
    ///
    /// This is the one place where the palette and the subject agree by luck: a real feral pigeon is
    /// grey with blue-green iridescence at the neck and orange-pink feet, and `haze`, `skyAccent` and
    /// `windowLit` already describe exactly that.
    static let pigeonBody = haze
    static let pigeonWing = haze * 0.82
    static let pigeonNeck = skyAccent
    static let pigeonBeak = windowLit
    static let pigeonEye = outline

    /// Other pigeons, drawn dark enough to read as silhouettes against the sky.
    ///
    /// **Legibility over realism, deliberately.** They share the player's rig, so at a glance the
    /// first build made them nearly indistinguishable from the bird you control — unacceptable in a
    /// game where touching one ends the run. Darkening them to a near-silhouette separates "you"
    /// from "hazard" instantly at any distance, and costs nothing: it is still `haze`, just further
    /// down. No new hue enters the palette.
    static let flockTint: Float = 0.34

    /// The payload. §7: abstract, white, no anatomy. A splat and nothing more.
    static let payload = white

    /// The predicted arc. Froggo 1's exact `trajectoryLine` stroke: white at 0.7 alpha.
    static let arc = white
    static let arcAlpha: Float = 0.7

    /// Landing ring, reachable. **Derived:** the Froggo green, the series' "yes" colour.
    static let ringReachable = green
    /// Landing ring, out of range. **Derived:** deliberately `windowLit`, not red — orange is already
    /// in the palette as the lit-window colour, so out-of-range reads as "not yet" rather than as an
    /// error, and no new hue enters the game. (The same argument froggo2 made for the same reason.)
    static let ringUnreachable = windowLit

    /// Vehicle paint: the palette used as a set. This is the one place the whole thing can appear at
    /// once without looking arbitrary, because a street of cars is *meant* to be varied.
    static let vehiclePaint: [SIMD3<Float>] = [
        green, greenAlt, windowLit, white, facade, skyAccent,
    ]
    static let vehicleGlass = outline * 1.6
    static let pedestrianBody = facade * 0.85
    static let pedestrianHead = haze

    static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF) / 255,
              Float((hex >> 8) & 0xFF) / 255,
              Float(hex & 0xFF) / 255)
    }
}
