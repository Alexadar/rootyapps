import Foundation

/// Water pipe sizing with velocity and erosion limits.
public enum PipeSizing {
    public static let minVelocityFPS: Double = 2
    public static let maxVelocityFPS: Double = 5    // erosion threshold

    public struct Check: Equatable, Sendable {
        public var velocityFPS: Double
        public var belowMin: Bool
        public var erodes: Bool
        public var inRange: Bool { !belowMin && !erodes }
    }

    /// Velocity (ft/s) of `gpm` through a nominal inside diameter (inches).
    public static func velocity(gpm: Double, insideDiameterIn d: Double) -> Double {
        let areaFt2 = Double.pi * pow(d / 12, 2) / 4
        guard areaFt2 > 0 else { return .infinity }
        return (gpm / 448.831) / areaFt2   // gpm -> ft³/s over area
    }

    public static func check(gpm: Double, insideDiameterIn d: Double) -> Check {
        let v = velocity(gpm: gpm, insideDiameterIn: d)
        return Check(velocityFPS: v, belowMin: v < minVelocityFPS, erodes: v > maxVelocityFPS)
    }
}
