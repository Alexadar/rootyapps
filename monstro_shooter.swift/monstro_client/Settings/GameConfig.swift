import Foundation

/// Game configuration that can be loaded from prod.json or SettingsManager
/// depending on the launch mode
struct GameConfig: Codable {
    let mapFilename: String
    let weaponId: Int
    let exoskeletonId: Int

    /// Get current game config based on launch mode
    /// - Production mode: loads from prod.json
    /// - Debug map selector mode: loads from SettingsManager
    static var current: GameConfig {
        if LaunchMode.current == .debugMapSelector {
            return fromSettings()
        } else {
            return fromProdConfig() ?? fallback
        }
    }

    /// Load config from prod.json bundle resource
    private static func fromProdConfig() -> GameConfig? {
        guard let url = Bundle.main.url(forResource: "prod", withExtension: "json") else {
            print("[GameConfig] prod.json not found in bundle")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(GameConfig.self, from: data)
            print("[GameConfig] Loaded from prod.json: map=\(config.mapFilename), weapon=\(config.weaponId), exo=\(config.exoskeletonId)")
            return config
        } catch {
            print("[GameConfig] Failed to load prod.json: \(error)")
            return nil
        }
    }

    /// Load config from SettingsManager (for debug map selector mode)
    private static func fromSettings() -> GameConfig {
        let config = GameConfig(
            mapFilename: SettingsManager.shared.selectedMapFilename,
            weaponId: SettingsManager.shared.selectedWeaponId,
            exoskeletonId: SettingsManager.shared.selectedExoskeletonId
        )
        print("[GameConfig] Loaded from SettingsManager: map=\(config.mapFilename), weapon=\(config.weaponId), exo=\(config.exoskeletonId)")
        return config
    }

    /// Fallback config if prod.json fails to load
    private static let fallback = GameConfig(
        mapFilename: "map_0014",
        weaponId: 1,
        exoskeletonId: 1
    )
}
