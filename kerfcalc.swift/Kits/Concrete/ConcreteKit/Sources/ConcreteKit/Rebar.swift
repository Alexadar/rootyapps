import Foundation

/// US rebar bar sizes (imperial #3–#11). Nominal diameter, cross-sectional area and unit weight
/// are the **ASTM A615** standard values (identical for Grade 40/60/75). For #3–#8 the number is the
/// diameter in eighths of an inch. Source: ASTM A615 / CRSI Manual of Standard Practice.
public enum BarSize: Int, CaseIterable, Identifiable, Sendable {
    case n3 = 3, n4, n5, n6, n7, n8, n9, n10, n11
    public var id: Int { rawValue }
    public var label: String { "#\(rawValue)" }

    public var diameterIn: Double {
        [3: 0.375, 4: 0.500, 5: 0.625, 6: 0.750, 7: 0.875,
         8: 1.000, 9: 1.128, 10: 1.270, 11: 1.410][rawValue]!
    }
    public var areaIn2: Double {
        [3: 0.11, 4: 0.20, 5: 0.31, 6: 0.44, 7: 0.60,
         8: 0.79, 9: 1.00, 10: 1.27, 11: 1.56][rawValue]!
    }
    public var weightLbPerFt: Double {
        [3: 0.376, 4: 0.668, 5: 1.043, 6: 1.502, 7: 2.044,
         8: 2.670, 9: 3.400, 10: 4.303, 11: 5.313][rawValue]!
    }
}

public enum Rebar {
    /// Weight of a straight bar run, pounds.
    public static func weight(_ size: BarSize, lengthFt: Double) -> Double { size.weightLbPerFt * lengthFt }

    /// Number of bars across a dimension at an on-center spacing, with a bar at each end.
    public static func barCount(dimensionFt: Double, spacingIn: Double) -> Int {
        spacingIn > 0 ? Int((dimensionFt * 12 / spacingIn).rounded(.down)) + 1 : 0
    }

    /// Total lineal feet of bar in a two-way slab mat (bars each direction at `spacingIn`).
    public static func matLinealFeet(lengthFt: Double, widthFt: Double, spacingIn: Double) -> Double {
        let runningLength = Double(barCount(dimensionFt: widthFt, spacingIn: spacingIn)) * lengthFt
        let runningWidth  = Double(barCount(dimensionFt: lengthFt, spacingIn: spacingIn)) * widthFt
        return runningLength + runningWidth
    }

    /// Total weight of a two-way slab mat, pounds.
    public static func matWeight(size: BarSize, lengthFt: Double, widthFt: Double, spacingIn: Double) -> Double {
        matLinealFeet(lengthFt: lengthFt, widthFt: widthFt, spacingIn: spacingIn) * size.weightLbPerFt
    }

    /// Tension lap-splice length, inches — the field **rule of thumb** 40×bar-diameter, min 12".
    /// NOT an ACI 318 design value (actual lap depends on f′c, grade, cover, spacing); a jobsite
    /// estimate only. Source: CRSI / ACI 318 §25.5 practical approximation.
    public static func lapLengthIn(_ size: BarSize, factor: Double = 40) -> Double {
        Swift.max(12, factor * size.diameterIn)
    }

    /// Standard 90° hook extension ≈ 12×bar-diameter, inches.
    public static func hookExtensionIn(_ size: BarSize) -> Double { 12 * size.diameterIn }
}
