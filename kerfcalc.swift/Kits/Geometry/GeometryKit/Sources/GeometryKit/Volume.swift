import Foundation

/// Solid-volume math for takeoffs, plus the construction volume conversions. Pure, stateless.
public enum Volume {
    public static let cubicFeetPerCubicYard = 27.0     // 3³
    public static let cubicInchesPerCubicFoot = 1728.0 // 12³

    public static func box(length l: Double, width w: Double, height h: Double) -> Double { l * w * h }
    public static func cylinder(radius r: Double, height h: Double) -> Double { .pi * r * r * h }
    public static func cylinder(diameter d: Double, height h: Double) -> Double { .pi * d * d / 4 * h }
    public static func cone(radius r: Double, height h: Double) -> Double { .pi * r * r * h / 3 }
    public static func sphere(radius r: Double) -> Double { 4.0 / 3.0 * .pi * r * r * r }

    public static func cubicFeetToYards(_ ft3: Double) -> Double { ft3 / cubicFeetPerCubicYard }
    public static func cubicYardsToFeet(_ yd3: Double) -> Double { yd3 * cubicFeetPerCubicYard }
    public static func cubicInchesToFeet(_ in3: Double) -> Double { in3 / cubicInchesPerCubicFoot }
}
