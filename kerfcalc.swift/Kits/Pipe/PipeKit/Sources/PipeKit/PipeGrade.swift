import Foundation

/// Drainage grade / fall on a horizontal run. Pure, stateless. Angles in degrees.
///
/// Plumbers express slope as **fall per foot** (¼″/ft, ⅛″/ft), estimators as a **percent**, and
/// drawings as a **ratio** (1:48). They are the same number in three costumes:
///
///     fall = run · fallPerFt      percent = fallPerFt ⁄ 12 · 100      1:N where N = 12 ⁄ fallPerFt
///
/// Cross-checked against the plumbing codes' minimum slopes — ¼″/ft (2.08 %, 1:48) for pipe up to
/// 2½″, ⅛″/ft (1.04 %, 1:96) above that (IPC/UPC; see PipeGradeOracleTests). Those minimums are
/// **code-cycle** values that vary by adopted edition and jurisdiction: this Kit computes the
/// arithmetic, it does not certify a design.
///
/// `percent` and `degrees` are the pipe-trades spelling of `FramingKit.Pitch.slopePercent` /
/// `angleDegrees` with the run fixed at 12″. Deliberately duplicated rather than imported — no Kit
/// here depends on another — and `kerfcalcTests` asserts the two spellings never drift apart.
public enum PipeGrade {
    private static let r2d = 180 / Double.pi

    /// Total fall over a run — `run(ft) · fallPerFt(in/ft)`, inches.
    public static func fallIn(runFeet: Double, fallInPerFt: Double) -> Double {
        runFeet * fallInPerFt
    }

    /// The grade a measured fall over a measured run works out to, inches per foot.
    public static func fallInPerFt(fallIn: Double, runFeet: Double) -> Double {
        runFeet != 0 ? fallIn / runFeet : 0
    }

    /// Grade as a percentage — `fallPerFt ⁄ 12 · 100`. ¼″/ft → 2.0833 %.
    public static func percent(fallInPerFt: Double) -> Double { fallInPerFt / 12 * 100 }

    /// Grade as the `N` in a 1:N ratio — `12 ⁄ fallPerFt`. ¼″/ft → 48. Level (0 fall) → 0.
    public static func ratioDenominator(fallInPerFt: Double) -> Double {
        fallInPerFt != 0 ? 12 / fallInPerFt : 0
    }

    /// Grade as an angle below horizontal — `atan(fallPerFt ⁄ 12)`, degrees.
    public static func degrees(fallInPerFt: Double) -> Double { atan2(fallInPerFt, 12) * r2d }

    /// Inverse of `percent` — the fall per foot a percentage grade means.
    public static func fallInPerFt(percent: Double) -> Double { percent / 100 * 12 }

    /// Inverse of `ratioDenominator` — the fall per foot a 1:N ratio means.
    public static func fallInPerFt(ratioDenominator n: Double) -> Double { n != 0 ? 12 / n : 0 }
}
