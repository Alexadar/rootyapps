import CoreGraphics

/// Pure bullet-spread math extracted from `GameScene.shoot`.
enum SpreadMath {
    /// Convert a pixel deviation (max spread at a reference distance) into an angular spread in radians.
    static func deviationToAngle(_ deviationPixels: CGFloat, referenceDistance: CGFloat = 500) -> CGFloat {
        return atan2(deviationPixels, referenceDistance)
    }
}
