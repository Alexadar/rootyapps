import Foundation

/// Right-triangle / roof-pitch math. Pure, stateless. All angles in degrees.
///
/// Roof pitch is expressed "X-in-12": rise of X inches over 12 inches of run. The angle is
/// `atan(rise/run)`; a slope's *diagonal* is the Pythagorean hypotenuse. Definitional trig,
/// cross-checked against published roof-pitch→angle tables (see PitchOracleTests).
public enum Pitch {
    private static let r2d = 180 / Double.pi

    /// Hypotenuse of a right triangle (rafter/diagonal from rise & run).
    public static func diagonal(rise: Double, run: Double) -> Double { (rise * rise + run * run).squareRoot() }

    /// Missing leg given the diagonal and one leg.
    public static func leg(diagonal d: Double, otherLeg a: Double) -> Double {
        let s = d * d - a * a
        return s > 0 ? s.squareRoot() : 0
    }

    /// Angle of the slope from horizontal, degrees.
    public static func angleDegrees(rise: Double, run: Double) -> Double { atan2(rise, run) * r2d }

    /// Grade/slope as a percentage (rise ÷ run × 100).
    public static func slopePercent(rise: Double, run: Double) -> Double { run != 0 ? rise / run * 100 : 0 }

    /// Pitch as rise-in-12 (the carpenter's "X/12").
    public static func riseInTwelve(rise: Double, run: Double) -> Double { run != 0 ? rise / run * 12 : 0 }

    /// Angle from an X-in-12 pitch, degrees. `atan(rise/12)`.
    public static func angleFromPitch(riseIn12: Double) -> Double { atan2(riseIn12, 12) * r2d }

    /// Rise-in-12 pitch from an angle in degrees.
    public static func pitchFromAngle(degrees: Double) -> Double { tan(degrees / r2d) * 12 }
}
