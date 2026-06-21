import Foundation

/// Pure FPS-selection rules extracted from `SettingsManager`.
enum DeviceFPS {
    /// Pass through `fps` if it's a supported option, otherwise return `fallback`.
    static func validated(_ fps: Int, options: [Int], fallback: Int = 60) -> Int {
        options.contains(fps) ? fps : fallback
    }

    /// Map an iOS device identifier (e.g. "iPhone15,2") to a preferred FPS tier.
    /// Pro/Max-era iPhones and recent iPads get 120; everything else 60.
    static func fps(forDeviceIdentifier identifier: String) -> Int {
        if identifier.contains("iPhone14") || identifier.contains("iPhone15") || identifier.contains("iPhone16") ||
            identifier.contains("iPad13") || identifier.contains("iPad14") {
            return 120
        }
        return 60
    }
}
