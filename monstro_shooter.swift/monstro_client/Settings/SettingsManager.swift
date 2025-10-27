import Foundation

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
            Keys.selectedMapFilename: "map_016"  // First map (orderNumber 0)
        ])
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
            return userDefaults.string(forKey: Keys.selectedMapFilename) ?? "map_016"
        }
        set {
            userDefaults.set(newValue, forKey: Keys.selectedMapFilename)
            print("[SettingsManager] Selected map: \(newValue)")
        }
    }

    /// Reset all settings to defaults
    func resetToDefaults() {
        bgmEnabled = true
        sfxEnabled = true
        selectedMapFilename = "map_016"
        print("[SettingsManager] Settings reset to defaults")
    }
}
