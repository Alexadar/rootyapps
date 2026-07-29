import Foundation

/// Solid-volume math for takeoffs, plus the construction volume conversions. Pure, stateless.
///
/// Oracle class: IDENTITY for the solids; **PUBLISHED** for the cubic-yard factor —
/// NIST SP 811 §B.8 gives cubic yard → cubic metre = 7.645549E−01, which is 0.9144³ and therefore
/// exactly 27 ft³ per yd³. See `AreaVolumeTests`.
public enum Volume {
    public static let cubicFeetPerCubicYard = 27.0      // 3³
    public static let cubicInchesPerCubicFoot = 1728.0  // 12³

    /// NIST SP 811 §B.8: cubic yard → cubic metre. Exact, being 0.9144³.
    public static let cubicMetresPerCubicYard = 0.9144 * 0.9144 * 0.9144

    public static func box(length l: Double, width w: Double, height h: Double) -> Double { l * w * h }
    public static func cylinder(radius r: Double, height h: Double) -> Double { .pi * r * r * h }
    public static func cylinder(diameter d: Double, height h: Double) -> Double { .pi * d * d / 4 * h }
    public static func cone(radius r: Double, height h: Double) -> Double { .pi * r * r * h / 3 }
    public static func sphere(radius r: Double) -> Double { 4.0 / 3.0 * .pi * r * r * r }

    public static func cubicFeetToYards(_ ft3: Double) -> Double { ft3 / cubicFeetPerCubicYard }
    public static func cubicYardsToFeet(_ yd3: Double) -> Double { yd3 * cubicFeetPerCubicYard }
    public static func cubicInchesToFeet(_ in3: Double) -> Double { in3 / cubicInchesPerCubicFoot }
    public static func cubicYardsToMetres(_ yd3: Double) -> Double { yd3 * cubicMetresPerCubicYard }
}

/// Concrete-volume takeoffs and bag counts. Pure, stateless.
///
/// MODEL CAVEAT: bag yields are the manufacturer's published figures (QUIKRETE Concrete Mix #1101
/// data sheet) — a commercial datasheet, not a standard, so they are labelled as such and are the
/// one number here a user may reasonably override. Waste percentage is an estimating convention,
/// explicitly not an oracle.
public enum Concrete {
    public static let bag80lbYieldFt3 = 0.60
    public static let bag60lbYieldFt3 = 0.45
    public static let bag40lbYieldFt3 = 0.30

    /// Slab / footing volume in ft³ from plan feet × plan feet × thickness in inches.
    public static func slabCubicFeet(lengthFt: Double, widthFt: Double, thicknessInches: Double) -> Double {
        lengthFt * widthFt * (thicknessInches / 12)
    }

    /// Cylindrical pour (column, post-hole, sonotube) in ft³ from diameter & depth in inches.
    public static func columnCubicFeet(diameterInches: Double, heightInches: Double) -> Double {
        let r = diameterInches / 2 / 12
        return .pi * r * r * (heightInches / 12)
    }

    public static func cubicYards(cubicFeet: Double) -> Double { cubicFeet / Volume.cubicFeetPerCubicYard }

    /// Volume with a waste/over-order allowance. `wastePct` is an editable convention, NOT an oracle.
    public static func withWaste(cubicFeet: Double, wastePct: Double) -> Double {
        cubicFeet * (1 + wastePct / 100)
    }

    /// Whole bags needed (rounded up) for a volume in ft³ at a given per-bag yield.
    public static func bags(cubicFeet: Double, yieldFt3: Double = bag80lbYieldFt3) -> Int {
        yieldFt3 > 0 ? Int((cubicFeet / yieldFt3).rounded(.up)) : 0
    }
}
