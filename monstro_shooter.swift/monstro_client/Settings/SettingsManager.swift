import Foundation
#if os(macOS)
import IOKit.ps
#endif

/// Settings manager singleton to handle persistent game settings using UserDefaults
///
/// Usage:
/// ```
/// // Get settings
/// let bgmEnabled = SettingsManager.shared.bgmEnabled
///
/// // Update settings (automatically persisted)
/// SettingsManager.shared.bgmEnabled = false
///
/// // Reset to defaults
/// SettingsManager.shared.resetToDefaults()
/// ```
class SettingsManager {
    static let shared = SettingsManager()

    private let userDefaults = UserDefaults.standard

    // Keys for UserDefaults
    private enum Keys {
        static let bgmEnabled = "settings.audio.bgmEnabled"
        static let sfxEnabled = "settings.audio.sfxEnabled"
        static let selectedMapFilename = "settings.game.selectedMapFilename"
        static let selectedDropPointId = "settings.game.selectedDropPointId"
        static let selectedWeaponId = "settings.game.selectedWeaponId"
        static let selectedExoskeletonId = "settings.game.selectedExoskeletonId"
        static let targetFPS = "settings.graphics.targetFPS"
    }

    private init() {
        // Register default values on first launch
        registerDefaults()
        print("[SettingsManager] Initialized - BGM: \(bgmEnabled), SFX: \(sfxEnabled)")
    }

    /// Register default settings values
    private func registerDefaults() {
        userDefaults.register(defaults: [
            Keys.bgmEnabled: true,
            Keys.sfxEnabled: true,
            Keys.selectedMapFilename: "map_0014",  // Test map with Bug + Berserker
            Keys.selectedDropPointId: 18,
            Keys.selectedWeaponId: 1,  // Default to pistol
            Keys.selectedExoskeletonId: 1,  // Default to standard suit
            Keys.targetFPS: Self.detectOptimalFPS()  // Auto-detect based on device
        ])
    }

    /// Detect optimal FPS based on device capabilities
    private static func detectOptimalFPS() -> Int {
        #if os(macOS)
        // Check if running on battery (laptop) vs plugged in
        // Also check thermal state if available
        if let powerSource = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(powerSource)?.takeRetainedValue() as? [CFTypeRef],
           !sources.isEmpty,
           let info = IOPSGetPowerSourceDescription(powerSource, sources[0])?.takeUnretainedValue() as? [String: Any],
           let isCharging = info[kIOPSIsChargingKey] as? Bool,
           !isCharging {
            // On battery - use 60 FPS to save power
            return 60
        }
        // Plugged in or desktop - use 120 FPS
        return 120
        #else
        // iOS: Check device model for performance tier
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }

        // Pro/Max models and newer iPads get 120 FPS
        if identifier.contains("iPhone14") || identifier.contains("iPhone15") || identifier.contains("iPhone16") ||
           identifier.contains("iPad13") || identifier.contains("iPad14") {
            return 120
        }
        // Older devices get 60 FPS
        return 60
        #endif
    }

    // MARK: - Audio Settings

    /// Get background music enabled state
    var bgmEnabled: Bool {
        get {
            return userDefaults.bool(forKey: Keys.bgmEnabled)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.bgmEnabled)
            print("[SettingsManager] BGM enabled: \(newValue)")
        }
    }

    /// Get sound effects enabled state
    var sfxEnabled: Bool {
        get {
            return userDefaults.bool(forKey: Keys.sfxEnabled)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.sfxEnabled)
            print("[SettingsManager] SFX enabled: \(newValue)")
        }
    }

    // MARK: - Game Settings

    /// Get/set selected map filename
    var selectedMapFilename: String {
        get {
            return userDefaults.string(forKey: Keys.selectedMapFilename) ?? "map_0014"
        }
        set {
            userDefaults.set(newValue, forKey: Keys.selectedMapFilename)
            print("[SettingsManager] Selected map: \(newValue)")
        }
    }

    /// Get/set selected drop point ID
    var selectedDropPointId: Int? {
        get {
            return userDefaults.object(forKey: Keys.selectedDropPointId) as? Int
        }
        set {
            userDefaults.set(newValue, forKey: Keys.selectedDropPointId)
            print("[SettingsManager] Selected drop point ID: \(newValue ?? -1)")
        }
    }

    /// Get/set selected weapon ID
    var selectedWeaponId: Int {
        get {
            return userDefaults.integer(forKey: Keys.selectedWeaponId)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.selectedWeaponId)
            print("[SettingsManager] Selected weapon ID: \(newValue)")
        }
    }

    /// Get/set selected exoskeleton ID
    var selectedExoskeletonId: Int {
        get {
            return userDefaults.integer(forKey: Keys.selectedExoskeletonId)
        }
        set {
            userDefaults.set(newValue, forKey: Keys.selectedExoskeletonId)
            print("[SettingsManager] Selected exoskeleton ID: \(newValue)")
        }
    }

    // MARK: - Graphics Settings

    /// Available FPS options
    static let fpsOptions: [Int] = [30, 60, 120]

    /// Get/set target FPS (30, 60, or 120)
    var targetFPS: Int {
        get {
            let fps = userDefaults.integer(forKey: Keys.targetFPS)
            // Validate stored value is in allowed options
            return Self.fpsOptions.contains(fps) ? fps : Self.detectOptimalFPS()
        }
        set {
            // Only allow valid FPS values
            let validFPS = Self.fpsOptions.contains(newValue) ? newValue : 60
            userDefaults.set(validFPS, forKey: Keys.targetFPS)
            print("[SettingsManager] Target FPS: \(validFPS)")
        }
    }

    /// Reset FPS to auto-detected optimal value
    func resetFPSToAuto() {
        targetFPS = Self.detectOptimalFPS()
    }

    /// Reset all settings to defaults
    func resetToDefaults() {
        bgmEnabled = true
        sfxEnabled = true
        selectedMapFilename = "map_0014"
        selectedDropPointId = 18
        selectedWeaponId = 1
        selectedExoskeletonId = 1
        targetFPS = Self.detectOptimalFPS()
        print("[SettingsManager] Settings reset to defaults")
    }
}
