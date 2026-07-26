import Foundation

/// Footing & wall concrete volumes (geometry). Pure, stateless. Returns ft³; use `cubicYards`.
public enum Footing {
    /// Continuous (strip) footing: length in feet, width & depth in inches.
    public static func continuousCubicFeet(lengthFt: Double, widthIn: Double, depthIn: Double) -> Double {
        lengthFt * (widthIn / 12) * (depthIn / 12)
    }
    /// Spread (pad) footing: all three dimensions in inches.
    public static func padCubicFeet(lengthIn: Double, widthIn: Double, depthIn: Double) -> Double {
        (lengthIn / 12) * (widthIn / 12) * (depthIn / 12)
    }
    /// Poured wall / stem wall: length & height in feet, thickness in inches.
    public static func wallCubicFeet(lengthFt: Double, heightFt: Double, thicknessIn: Double) -> Double {
        lengthFt * heightFt * (thicknessIn / 12)
    }
    public static func cubicYards(_ ft3: Double) -> Double { ft3 / 27 }
}
