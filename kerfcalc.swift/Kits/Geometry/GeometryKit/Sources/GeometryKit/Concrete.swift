import Foundation

/// Concrete-volume takeoffs and bag counts. Pure, stateless.
///
/// Bag yields are the manufacturer's published figures (QUIKRETE Concrete Mix #1101 data sheet):
/// 80 lb → 0.60 ft³, 60 lb → 0.45 ft³, 40 lb → 0.30 ft³. 27 ft³ per cubic yard.
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
        let r = diameterInches / 2 / 12          // ft
        return .pi * r * r * (heightInches / 12)
    }

    public static func cubicYards(cubicFeet: Double) -> Double { cubicFeet / 27 }

    /// Volume with a waste/over-order allowance (pros typically order 5–10 % extra). `wastePct` is an
    /// editable convention, NOT an oracle constant.
    public static func withWaste(cubicFeet: Double, wastePct: Double) -> Double { cubicFeet * (1 + wastePct / 100) }

    /// Whole bags needed (rounded up) for a volume in ft³ at a given per-bag yield.
    public static func bags(cubicFeet: Double, yieldFt3: Double = bag80lbYieldFt3) -> Int {
        yieldFt3 > 0 ? Int((cubicFeet / yieldFt3).rounded(.up)) : 0
    }
}
