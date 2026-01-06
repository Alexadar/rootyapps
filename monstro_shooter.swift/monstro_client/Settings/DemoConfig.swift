import Foundation

/// Hardcoded demo configuration for normal debug/release builds
/// Map selector is only available in special debug mode (--debug-map-selector)
enum DemoConfig {
    /// Demo map filename (without .json extension)
    static let mapFilename = "map_0014"

    /// Default weapon ID (1 = pistol)
    static let weaponId = 1

    /// Default exoskeleton ID (1 = standard suit)
    static let exoskeletonId = 1

    /// Default drop point ID
    static let dropPointId = 18
}
