import Foundation

/// Roofing quantity math. Pure, stateless.
///
/// A sloped roof's surface area = plan (footprint) area × the *pitch multiplier*
/// √(1 + (rise/12)²) — the slope factor. One roofing "square" = 100 ft² of roof surface.
/// (Published roofing slope-factor convention: roofpitch.net, roofobservations.com.)
public enum Roofing {
    /// Slope factor for an X-in-12 pitch. 6/12 → √1.25 = 1.11803.
    public static func pitchMultiplier(riseIn12: Double) -> Double {
        (1 + pow(riseIn12 / 12, 2)).squareRoot()
    }

    /// Actual sloped roof area from the plan footprint area and the pitch.
    public static func roofArea(planAreaFt2: Double, riseIn12: Double) -> Double {
        planAreaFt2 * pitchMultiplier(riseIn12: riseIn12)
    }

    /// Roofing squares (100 ft² each) from a roof-surface area.
    public static func squares(roofAreaFt2: Double) -> Double { roofAreaFt2 / 100 }

    /// Squares including a waste allowance (default 10 % — an editable estimating convention,
    /// NOT a published constant).
    public static func squaresWithWaste(roofAreaFt2: Double, wastePct: Double = 10) -> Double {
        squares(roofAreaFt2: roofAreaFt2) * (1 + wastePct / 100)
    }
}
