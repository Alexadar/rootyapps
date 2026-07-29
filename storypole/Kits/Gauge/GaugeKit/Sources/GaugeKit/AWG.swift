import Foundation

/// American Wire Gage — **conductor diameter only**.
///
/// Pure, stateless.
///
/// ## Oracle: PUBLISHED
///
/// NBS Handbook 100, *Copper Wire Tables*, §2.1 "General Use of the American Wire Gage"
/// (US Government work, public domain), verbatim:
///
/// > *"the diameter of No. 0000 is defined as 0.4600 inch and of No. 36 as 0.0050 inch. There are
/// > 38 sizes between ... hence the ratio of any diameter to the diameter of the next larger gage
/// > number = ³⁹√92 = 1.122 932 2."*
///
/// https://nvlpubs.nist.gov/nistpubs/Legacy/hb/nbshandbook100.pdf — retrieved 2026-07-29, HTTP 200.
///
/// (The handoff cited §2.2; the passage is in §2.1.)
///
/// ## MODEL CAVEAT — the liability line
///
/// This computes a **dimension**, nothing else. Ampacity, conductor sizing, voltage drop and box
/// fill are deliberately out of scope: they are code-governed, jurisdiction-specific, and carry
/// real safety consequences. See `docs/storypole_oracle_gate_2026-07-29.md` §5. A wire diameter is
/// a measurement, which is what this app does; how much current it may carry is not.
public enum AWG {

    /// The two anchor diameters that define the gage, in inches. Both are *defined*, not measured.
    public static let anchor0000Inch = 0.4600
    public static let anchor36Inch   = 0.0050

    /// The 39th root of 92 — the ratio between successive gage numbers.
    /// HB 100 §2.1 prints this as 1.122 932 2.
    public static let ratio = pow(anchor0000Inch / anchor36Inch, 1.0 / 39.0)

    /// The gage numbers this formula is defined over: 0000 (−3) through 36.
    /// Sizes beyond 36 exist in tables but are outside the two defining anchors.
    public static let definedRange: ClosedRange<Int> = -3...36

    /// Conductor diameter in inches for gage `n`.
    ///
    /// `d(n) = 0.005 × 92^((36 − n) / 39)` inch, which is the closed form of the geometric
    /// progression HB 100 §2.1 describes. Gage numbers 0, 00, 000, 0000 are `n = 0, −1, −2, −3`.
    public static func diameterInch(gage n: Int) -> Double {
        anchor36Inch * pow(92.0, Double(36 - n) / 39.0)
    }

    /// Conductor diameter in millimetres (25.4 mm/in exactly, per the 1959 refixing).
    public static func diameterMillimetres(gage n: Int) -> Double {
        diameterInch(gage: n) * 25.4
    }

    /// Cross-sectional area in circular mils. HB 100 §2.1: *"A mil is 0.001 inch, and the 'area'
    /// in circular mils is the square of the diameter in mils."*
    public static func areaCircularMils(gage n: Int) -> Double {
        let mils = diameterInch(gage: n) * 1000
        return mils * mils
    }

    /// Cross-sectional area in square inches (true area, πd²/4 — not circular mils).
    public static func areaSquareInches(gage n: Int) -> Double {
        let d = diameterInch(gage: n)
        return .pi * d * d / 4
    }

    /// Display name: gage 0 and below are written 0, 00, 000, 0000.
    public static func name(gage n: Int) -> String {
        n >= 1 ? "\(n) AWG" : String(repeating: "0", count: 1 - n) + " AWG"
    }
}
