import Foundation

/// Roof-pitch math. Pure, stateless. All angles in degrees.
///
/// Roof pitch is expressed "X-in-12": rise of X inches over 12 inches of run. The angle is
/// `atan(rise/run)`. Definitional trigonometry, cross-checked against published roof-pitch→angle
/// tables in `PitchOracleTests`.
///
/// Oracle class: IDENTITY.
///
/// Ported from `kerfcalc.swift/Kits/Framing/FramingKit/Sources/FramingKit/Pitch.swift`.
/// Pitch three ways matters because three trades each use a different one — this is the wound in
/// RedX Roof, 1★: *"Following the measurements for hip and Jack rafters to the 16th came up with
/// the wrong measurements and a lot of wasted material."*
public enum Pitch {
    private static let r2d = 180 / Double.pi

    /// Angle of the slope from horizontal, degrees.
    public static func angleDegrees(rise: Double, run: Double) -> Double { atan2(rise, run) * r2d }

    /// Grade/slope as a percentage (rise ÷ run × 100).
    public static func slopePercent(rise: Double, run: Double) -> Double { run != 0 ? rise / run * 100 : 0 }

    /// Pitch as rise-in-12 (the carpenter's "X/12").
    public static func riseInTwelve(rise: Double, run: Double) -> Double { run != 0 ? rise / run * 12 : 0 }

    /// Angle from an X-in-12 pitch, degrees. `atan(rise/12)`.
    public static func angleFromPitch(riseIn12 rise: Double) -> Double { atan2(rise, 12) * r2d }

    /// The X-in-12 pitch corresponding to an angle.
    public static func pitchFromAngle(degrees d: Double) -> Double { tan(d / r2d) * 12 }

    /// Slope factor / pitch multiplier: rafter length per unit of horizontal run.
    /// `√(1 + (rise/12)²)` — a 6/12 roof is √1.25 = 1.118034.
    public static func pitchMultiplier(riseIn12 rise: Double) -> Double {
        (1 + (rise / 12) * (rise / 12)).squareRoot()
    }

    /// Sloped area from plan (footprint) area — the roofing takeoff.
    public static func slopedArea(planArea: Double, riseIn12 rise: Double) -> Double {
        planArea * pitchMultiplier(riseIn12: rise)
    }
}
