import Foundation

/// Material-quantity estimates for takeoffs. Pure, stateless.
///
/// Coverage/coursing constants below are published; **waste percentages are editable estimating
/// conventions, NOT published constants** and are labelled as such.
public enum Estimate {
    // MARK: Drywall
    /// A 4'×8' sheet = 32 ft² (geometry).
    public static let drywallSheet4x8Ft2 = 32.0
    public static func drywallSheets(areaFt2: Double, sheetFt2: Double = drywallSheet4x8Ft2,
                                     wastePct: Double = 10 /* NOT oracle-backed: editable */) -> Int {
        sheetFt2 > 0 ? Int((areaFt2 / sheetFt2 * (1 + wastePct / 100)).rounded(.up)) : 0
    }

    // MARK: Paint
    /// Typical latex coverage ≈ 350 ft²/gal per coat (paint-manufacturer TDS range 350–400).
    public static let paintCoverageFt2PerGal = 350.0
    public static func paintGallons(areaFt2: Double, coats: Int = 2,
                                    coverageFt2PerGal: Double = paintCoverageFt2PerGal) -> Double {
        coverageFt2PerGal > 0 ? areaFt2 * Double(coats) / coverageFt2PerGal : 0
    }

    // MARK: Masonry (published rules of thumb)
    /// Modular brick with 3/8" joints ≈ 6.86 brick per ft² of wall (Brick Industry Assoc. rule).
    public static let modularBrickPerFt2 = 6.86
    /// 8×8×16 CMU ≈ 1.125 block per ft² of wall — 1 ÷ (8/12 · 16/12) face area (NCMA/geometry).
    public static let cmu8x16PerFt2 = 1.125

    public static func units(areaFt2: Double, perFt2: Double,
                             wastePct: Double = 5 /* NOT oracle-backed: editable */) -> Int {
        Int((areaFt2 * perFt2 * (1 + wastePct / 100)).rounded(.up))
    }

    // MARK: Lumber (borrowed from KerfKit.Stock — board-foot = 144 in³)
    /// Board feet: T″ · W″ · L′ / 12.
    public static func boardFeet(thicknessIn t: Double, widthIn w: Double, lengthFt l: Double) -> Double {
        t * w * l / 12
    }
    /// Board feet with length in inches: T″ · W″ · L″ / 144.
    public static func boardFeet(thicknessIn t: Double, widthIn w: Double, lengthIn l: Double) -> Double {
        t * w * l / 144
    }
}
