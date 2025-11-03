import Foundation

/// Map configuration matching JSON structure from database
struct MapConfig: Codable, Identifiable {
    let id: Int
    let ownerName: String?
    let dropPointId: Int?
    let ownerId: String?
    let energyCost: Int
    let landingDuration: Int
    let gameResource: String
    let country: String?
    let lastRenameDate: String?
    let renameCost: Int
    let renameCostMult: Int
    let removed: Bool
    let orderNumber: Int
    let defaultNameLocalizations: [String: String]
    let descriptionLocalizations: [String: String]
    let monsterSpawnWaves: [SpawnWave]
    let monsterTypes: [MonsterTypeAvailability]
    let maximumVictims: [String: Int]

    struct SpawnWave: Codable {
        let startTime: Int
        let count: Int
    }

    struct MonsterTypeAvailability: Codable {
        let startTime: Int
        let monsterTypeIds: [Int]
    }

    /// Get localized name (defaults to ru-ru then en-us)
    func getLocalizedName() -> String {
        return defaultNameLocalizations["ru-ru"]
            ?? defaultNameLocalizations["en-us"]
            ?? "Map \(id)"
    }

    /// Get localized description
    func getLocalizedDescription() -> String {
        return descriptionLocalizations["ru-ru"]
            ?? descriptionLocalizations["en-us"]
            ?? ""
    }

    /// Load map by filename (e.g. "map_017")
    static func load(filename: String) -> MapConfig? {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json", subdirectory: "MapConfigs") else {
            print("MapConfig: Failed to find \(filename).json")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let config = try decoder.decode(MapConfig.self, from: data)
            return config
        } catch {
            print("MapConfig: Failed to decode \(filename).json - \(error)")
            return nil
        }
    }

    /// Load all maps from all_maps.json
    static func loadAll() -> [MapConfig] {
        guard let url = Bundle.main.url(forResource: "all_maps", withExtension: "json") else {
            print("MapConfig: Failed to find all_maps.json in bundle.")
            return []
        }
        print("MapConfig: Found all_maps.json at URL: \(url.absoluteString)")

        do {
            let data = try Data(contentsOf: url)
            print("MapConfig: Successfully loaded data from all_maps.json. Data size: \(data.count) bytes")
            let decoder = JSONDecoder()
            let configs = try decoder.decode([MapConfig].self, from: data)
            print("MapConfig: Successfully decoded \(configs.count) maps from all_maps.json")
            return configs.sorted { $0.orderNumber < $1.orderNumber }
        } catch {
            print("MapConfig: Failed to decode all_maps.json - \(error)")
            return []
        }
    }
}
