import Foundation

/// Roof-rafter math using the framing-square "bridge measure" (length per foot of run).
/// Pure, stateless. `rise` is the pitch as rise-in-12 (e.g. 6 for a 6/12 roof).
///
/// Values reproduce the numbers printed on a physical framing square's rafter table
/// (see RafterOracleTests): common = √(rise²+12²) per foot of run; hip/valley = √(rise²+(12√2)²)
/// = √(rise²+288) per foot of *common* run, because a regular hip's plan run is the 45° diagonal
/// (unit run 12√2 = 16.97"). Reference: NAVEDTRA 14044 "Framing Roofs" (public domain); framing-
/// square rafter table.
public enum Rafter {
    private static let r2d = 180 / Double.pi

    /// Common rafter length per foot of run — the framing-square "bridge measure".
    public static func commonPerFootRun(rise: Double) -> Double { (rise * rise + 144).squareRoot() }

    /// Hip/valley rafter length per foot of *common* run.
    public static func hipValleyPerFootRun(rise: Double) -> Double { (rise * rise + 288).squareRoot() }

    /// Regular-hip unit run: the 45° diagonal of the 12" unit square, 12√2 ≈ 16.97".
    public static let hipUnitRun = 12 * Double(2).squareRoot()

    /// Total common-rafter line length for a horizontal run in feet (no overhang / HAP).
    public static func commonLength(rise: Double, runFeet: Double) -> Double {
        commonPerFootRun(rise: rise) * runFeet
    }

    /// Total hip/valley line length for a given *common* run in feet.
    public static func hipValleyLength(rise: Double, commonRunFeet: Double) -> Double {
        hipValleyPerFootRun(rise: rise) * commonRunFeet
    }

    /// Plumb-cut angle (from level), degrees — the tail/ridge cut of a common rafter. `atan(rise/12)`.
    public static func plumbCutDegrees(rise: Double) -> Double { atan2(rise, 12) * r2d }

    /// Level (seat) cut angle, degrees — complement of the plumb cut.
    public static func levelCutDegrees(rise: Double) -> Double { 90 - plumbCutDegrees(rise: rise) }

    /// Common difference of jack rafters: how much shorter each successive jack is, for an
    /// on-center spacing in inches. = spacing × (common length per foot of run) / 12.
    public static func jackCommonDifference(rise: Double, spacingInches: Double) -> Double {
        spacingInches * commonPerFootRun(rise: rise) / 12
    }

    /// Length of the n-th jack rafter (n = 1 is the shortest) given the longest run.
    public static func jackLength(rise: Double, longestRunFeet: Double, spacingInches: Double, index n: Int) -> Double {
        let full = commonLength(rise: rise, runFeet: longestRunFeet)
        return max(0, full - jackCommonDifference(rise: rise, spacingInches: spacingInches) * Double(n))
    }

    /// Slope factor — rafter length per inch of horizontal run (= common-per-foot-run ⁄ 12).
    public static func slopeFactor(rise: Double) -> Double { commonPerFootRun(rise: rise) / 12 }

    /// Ridge shortening, measured ALONG the rafter: half the ridge thickness (horizontal) × slope factor.
    /// The run is normally taken to the centre of the ridge, so the rafter is cut back half the ridge.
    public static func ridgeDeductionIn(rise: Double, ridgeThicknessIn: Double) -> Double {
        ridgeThicknessIn / 2 * slopeFactor(rise: rise)
    }

    /// Overhang (tail) length ALONG the rafter for a horizontal overhang, inches.
    public static func overhangAlongIn(rise: Double, overhangIn: Double) -> Double {
        overhangIn * slopeFactor(rise: rise)
    }

    /// Actual rafter cut length, inches: the theoretical line length, shortened for half the ridge and
    /// lengthened by the tail. This is the length a framer cuts (ridge-plumb to tail-plumb).
    public static func actualLength(rise: Double, runFeet: Double, ridgeThicknessIn: Double, overhangIn: Double) -> Double {
        commonLength(rise: rise, runFeet: runFeet)
            - ridgeDeductionIn(rise: rise, ridgeThicknessIn: ridgeThicknessIn)
            + overhangAlongIn(rise: rise, overhangIn: overhangIn)
    }
}
