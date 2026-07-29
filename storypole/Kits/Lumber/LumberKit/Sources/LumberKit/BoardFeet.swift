import Foundation
import DimensionKit

/// Board measure, and the conversion this app deliberately refuses to perform.
///
/// Pure, stateless.
///
/// ## Oracle: PUBLISHED
///
/// NIST Voluntary Product Standard **PS 20-20**, *American Softwood Lumber Standard*, January 2020,
/// §2.2 "Board measure" (US Government work, public domain), verbatim:
///
/// > *"The number of board feet in a piece of lumber is obtained by multiplying the nominal
/// > thickness in inches or fraction of an inch by the nominal width in feet by the length in feet."*
///
/// https://www.nist.gov/document/doc-ps-20-20-american-softwood-lumber-standard — retrieved
/// 2026-07-29, HTTP 200. (The handoff cited "PS 20-25"; no such edition exists — that URL 404s.)
public enum BoardFeet {

    /// Board feet from nominal dimensions, exact.
    ///
    /// `BF = T″ × (W″ / 12) × L′`, which is the standard's wording with the width converted from
    /// inches to feet. Held as a `Rational` because the common answers are thirds — a 2×4×8 is
    /// exactly 5⅓ board feet, not 5.33.
    public static func exact(thicknessIn t: Rational, widthIn w: Rational, lengthFt l: Rational) -> Rational {
        t * (w / Rational(12)) * l
    }

    /// Board feet with the length also in inches: `BF = T″ × W″ × L″ / 144`.
    public static func exact(thicknessIn t: Rational, widthIn w: Rational, lengthIn l: Rational) -> Rational {
        t * w * l / Rational(144)
    }

    public static func value(thicknessIn t: Double, widthIn w: Double, lengthFt l: Double) -> Double {
        t * w * l / 12
    }

    public static func value(thicknessIn t: Double, widthIn w: Double, lengthIn l: Double) -> Double {
        t * w * l / 144
    }

    /// Board feet for a whole parcel of identical pieces.
    public static func exact(pieces n: Int, thicknessIn t: Rational, widthIn w: Rational,
                             lengthFt l: Rational) -> Rational {
        Rational(Int64(n)) * exact(thicknessIn: t, widthIn: w, lengthFt: l)
    }

    // MARK: - The refusal

    /// Why board feet are not convertible to cubic metres. This app states it; no other does.
    ///
    /// PS 20-20 App. B, verbatim:
    ///
    /// > *"CAUTION: Use great care when converting board feet, based on NOMINAL cross-sectional
    /// > dimensions, to cubic meters of lumber, based on DRESSED cross-sectional dimensions."*
    ///
    /// A 2×4 is billed as 2″ × 4″ and delivered as 1½″ × 3½″ — 65.6 % of the nominal section. So a
    /// board-foot figure and a cubic-metre figure describe different solids, and dividing one by
    /// the other yields a number that means nothing. There is deliberately **no**
    /// `boardFeetToCubicMetres` function in this Kit.
    public static let cubicMetreCaution = """
        Board feet are based on NOMINAL dimensions; cubic metres are based on DRESSED dimensions. \
        Converting between them is not a legitimate unit conversion. \
        NIST PS 20-20, Appendix B: "CAUTION: Use great care when converting board feet, based on \
        NOMINAL cross-sectional dimensions, to cubic meters of lumber, based on DRESSED \
        cross-sectional dimensions."
        """

    /// The honest alternative: compute a true volume from the **dressed** section, which is a real
    /// solid and therefore really is convertible. Returns `nil` for a nominal size the standard
    /// does not tabulate, rather than guessing at its dressed dimensions.
    public static func dressedCubicFeet(nominalThicknessIn t: Rational, nominalWidthIn w: Rational,
                                        lengthFt l: Rational, seasoning: DressedSize.Seasoning = .dry) -> Rational? {
        guard let dt = DressedSize.dressed(nominalIn: t, seasoning: seasoning),
              let dw = DressedSize.dressed(nominalIn: w, seasoning: seasoning) else { return nil }
        return (dt / Rational(12)) * (dw / Rational(12)) * l
    }
}
