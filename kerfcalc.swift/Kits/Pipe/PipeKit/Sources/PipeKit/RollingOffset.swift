import Foundation

/// Rolling offset — an offset that moves in two directions at once. Pure, stateless. Angles in degrees.
///
/// When a run must shift both **set** (vertically) and **roll** (horizontally), the two combine into a
/// single **true offset** in the tilted plane that contains both fittings:
///
///     trueOffset = √(set² + roll²)      travel = trueOffset · csc θ      run = trueOffset · cot θ
///
/// There are **two distinct angles** in a rolling offset and they are easy to confuse:
///  • the **fitting angle** θ — the elbow you buy (45°, 22½°, …), measured in the tilted plane;
///  • the **roll angle** — `atan(roll ⁄ set)`, how far that plane is rotated off vertical. It tells
///    the fitter how far to roll the fitting, and it does not change the travel.
///
/// Reduces exactly to `PipeOffset` when roll = 0 (see RollingOffsetOracleTests).
public enum RollingOffset {
    private static let r2d = 180 / Double.pi

    /// The single offset the two directions combine into — `√(set² + roll²)`, the 3-D hypotenuse.
    public static func trueOffsetIn(setIn: Double, rollIn: Double) -> Double {
        (setIn * setIn + rollIn * rollIn).squareRoot()
    }

    /// How far the offset plane is rotated off vertical — `atan(roll ⁄ set)`, degrees.
    /// Roll 0 → 0° (a plain vertical offset); set 0 → 90° (a purely horizontal roll).
    public static func rollAngleDeg(setIn: Double, rollIn: Double) -> Double {
        (setIn == 0 && rollIn == 0) ? 0 : atan2(rollIn, setIn) * r2d
    }

    /// Everything the fitter needs for one rolling offset at a chosen fitting angle.
    public static func solve(setIn: Double, rollIn: Double,
                             fittingAngleDeg angleDeg: Double) -> RollingOffsetResult {
        let trueOffset = trueOffsetIn(setIn: setIn, rollIn: rollIn)
        return RollingOffsetResult(
            trueOffsetIn: trueOffset,
            travelIn: PipeOffset.travelIn(setIn: trueOffset, fittingAngleDeg: angleDeg),
            runIn: PipeOffset.runIn(setIn: trueOffset, fittingAngleDeg: angleDeg),
            rollAngleDeg: rollAngleDeg(setIn: setIn, rollIn: rollIn)
        )
    }
}

/// One solved rolling offset. All lengths in inches, angles in degrees.
public struct RollingOffsetResult: Equatable, Sendable {
    /// `√(set² + roll²)` — the offset actually being made, in the tilted plane.
    public let trueOffsetIn: Double
    /// Diagonal piece between the two fittings.
    public let travelIn: Double
    /// Horizontal distance the offset consumes along the original line.
    public let runIn: Double
    /// Rotation of the offset plane off vertical, `atan(roll ⁄ set)`.
    public let rollAngleDeg: Double
}
