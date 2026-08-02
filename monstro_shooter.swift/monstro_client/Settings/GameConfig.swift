import Foundation

/// Swipe direction for map transitions (TikTok-style vertical)
enum SwipeDirection {
    case up    // Next map
    case down  // Previous map
}

/// Protocol for receiving swipe events
protocol SwipeDelegate: AnyObject {
    func didSwipe(direction: SwipeDirection)
}

/// Game configuration that can be loaded from prod.json or SettingsManager
/// depending on the launch mode
struct GameConfig: Codable {
    // Support both old single mapFilename and new array format
    let mapFilename: String?
    let mapFilenames: [String]?
    let weaponId: Int
    let exoskeletonId: Int

    /// Shared instance for map carousel tracking
    static var shared = GameConfigManager()

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

            // Initialize shared manager with map list
            if let maps = config.mapFilenames, !maps.isEmpty {
                shared.mapFilenames = maps
                print("[GameConfig] Loaded \(maps.count) maps from prod.json")
            } else if let singleMap = config.mapFilename {
                shared.mapFilenames = [singleMap]
                print("[GameConfig] Loaded single map from prod.json: \(singleMap)")
            }

            print("[GameConfig] Loaded from prod.json: map=\(shared.currentMapFilename), weapon=\(config.weaponId), exo=\(config.exoskeletonId)")
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
            mapFilenames: nil,
            weaponId: SettingsManager.shared.selectedWeaponId,
            exoskeletonId: SettingsManager.shared.selectedExoskeletonId
        )
        // In debug mode, use single map
        shared.mapFilenames = [SettingsManager.shared.selectedMapFilename]
        print("[GameConfig] Loaded from SettingsManager: map=\(shared.currentMapFilename), weapon=\(config.weaponId), exo=\(config.exoskeletonId)")
        return config
    }

    /// Fallback config if prod.json fails to load
    private static let fallback = GameConfig(
        mapFilename: "map_0014",
        mapFilenames: nil,
        weaponId: 1,
        exoskeletonId: 1
    )
}

/// Manages map carousel state (current index, next/prev navigation)
class GameConfigManager {
    var mapFilenames: [String] = ["map_0014"]
    var currentMapIndex: Int = 0

    var currentMapFilename: String {
        guard !mapFilenames.isEmpty else { return "map_0014" }
        return mapFilenames[currentMapIndex]
    }

    var mapCount: Int {
        mapFilenames.count
    }

    func nextMap() -> String {
        guard !mapFilenames.isEmpty else { return "map_0014" }
        currentMapIndex = (currentMapIndex + 1) % mapFilenames.count
        print("[GameConfigManager] Switched to next map: \(currentMapFilename) (index \(currentMapIndex)/\(mapFilenames.count))")
        return currentMapFilename
    }

    func previousMap() -> String {
        guard !mapFilenames.isEmpty else { return "map_0014" }
        currentMapIndex = (currentMapIndex - 1 + mapFilenames.count) % mapFilenames.count
        print("[GameConfigManager] Switched to previous map: \(currentMapFilename) (index \(currentMapIndex)/\(mapFilenames.count))")
        return currentMapFilename
    }

    func reset() {
        currentMapIndex = 0
    }
}
