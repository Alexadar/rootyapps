import Foundation

/// Ready-mix ordering. A standard full mixer truck carries ≈ 10 yd³ (NRMCA typical 8–11 yd³);
/// most plants charge a short-load fee below a minimum (≈ 1 yd³). Values editable.
public enum ReadyMix {
    public static let truckCapacityYd3 = 10.0

    public static func truckLoads(cubicYards: Double, capacity: Double = truckCapacityYd3) -> Int {
        capacity > 0 ? Int((cubicYards / capacity).rounded(.up)) : 0
    }
    public static func isShortLoad(cubicYards: Double, minimum: Double = 1.0) -> Bool { cubicYards < minimum }
}

/// Contraction (control) joints in a slab-on-grade. ACI 360R rule of thumb: max joint spacing =
/// 24–36 × slab thickness (inches), i.e. 2–3 × thickness expressed in feet (4" slab → 8–12 ft).
public enum ControlJoints {
    /// (min, max) recommended joint spacing in feet for a slab thickness in inches.
    public static func spacingRangeFeet(thicknessIn t: Double) -> (min: Double, max: Double) { (2 * t, 3 * t) }

    /// Number of interior joints along a run, using the max recommended spacing.
    public static func joints(lengthFt: Double, thicknessIn t: Double) -> Int {
        let s = 3 * t
        return s > 0 ? Swift.max(0, Int((lengthFt / s).rounded(.up)) - 1) : 0
    }
}

/// CMU core grout. Fully-grouted 8" block wall ≈ 2.1 yd³ (56 ft³) of grout per 100 ft² of wall
/// face. Source: NCMA TEK 3-2A "Grouting Concrete Masonry Walls".
public enum Grout {
    public static let fullyGrouted8inFt3PerFt2 = 0.56    // 56 ft³ / 100 ft²

    public static func cubicFeet(wallAreaFt2: Double, factorFt3PerFt2: Double = fullyGrouted8inFt3PerFt2) -> Double {
        wallAreaFt2 * factorFt3PerFt2
    }
    public static func cubicYards(wallAreaFt2: Double, factorFt3PerFt2: Double = fullyGrouted8inFt3PerFt2) -> Double {
        cubicFeet(wallAreaFt2: wallAreaFt2, factorFt3PerFt2: factorFt3PerFt2) / 27
    }
}

/// Pavers & segmental retaining-wall block. Counts are geometric; pattern **waste %** is an editable
/// estimating convention (running bond ≈ 5 %, herringbone/45° ≈ 10–15 %), not a published constant.
public enum Hardscape {
    /// Pavers per ft² from a paver face size in inches (a 4"×8" paver → 4.5/ft²).
    public static func paversPerFt2(lengthIn: Double, widthIn: Double) -> Double {
        let face = lengthIn * widthIn
        return face > 0 ? 144 / face : 0
    }
    public static func paverCount(areaFt2: Double, lengthIn: Double, widthIn: Double, wastePct: Double) -> Int {
        Int((areaFt2 * paversPerFt2(lengthIn: lengthIn, widthIn: widthIn) * (1 + wastePct / 100)).rounded(.up))
    }
    public static func courses(wallHeightIn: Double, blockHeightIn: Double) -> Int {
        blockHeightIn > 0 ? Int((wallHeightIn / blockHeightIn).rounded(.up)) : 0
    }
    public static func wallBlockCount(wallLengthFt: Double, wallHeightIn: Double,
                                      blockLengthIn: Double, blockHeightIn: Double) -> Int {
        guard blockLengthIn > 0 else { return 0 }
        let perCourse = wallLengthFt * 12 / blockLengthIn
        return Int((perCourse * Double(courses(wallHeightIn: wallHeightIn, blockHeightIn: blockHeightIn))).rounded(.up))
    }
}
