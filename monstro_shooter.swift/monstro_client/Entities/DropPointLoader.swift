
import Foundation

/// Represents a drop point in the game.
struct DropPoint: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let nameEn: String?

    enum CodingKeys: String, CodingKey {
        case id, name, nameEn
    }
}

/// Loads and manages drop points from map configurations.
class DropPointLoader {

    /// Cache for loaded drop points
    private static var cachedDropPoints: [DropPoint]?

    /// Loads all drop points from the JSON resource file
    static func loadAllDropPoints() -> [DropPoint] {
        // Return cached drop points if available
        if let cached = cachedDropPoints {
            print("[DropPointLoader] Returning \(cached.count) cached drop points")
            return cached
        }

        print("[DropPointLoader] Loading drop points from JSON...")

        // Try to load from droppoints.json resource
        guard let url = Bundle.main.url(forResource: "droppoints", withExtension: "json") else {
            print("[DropPointLoader] ERROR: Failed to find droppoints.json in bundle")
            return loadDropPointsFromMaps() // Fallback to inferring from maps
        }

        print("[DropPointLoader] Found droppoints.json at: \(url.path)")

        do {
            let data = try Data(contentsOf: url)
            print("[DropPointLoader] Loaded \(data.count) bytes from droppoints.json")
            let decoder = JSONDecoder()
            let dropPoints = try decoder.decode([DropPoint].self, from: data)
            print("[DropPointLoader] Successfully decoded \(dropPoints.count) drop points from JSON")

            // Print first few drop points for debugging
            for (index, dp) in dropPoints.prefix(3).enumerated() {
                print("[DropPointLoader]   \(index): id=\(dp.id), name=\(dp.name)")
            }

            // Filter to only include drop points that have maps
            let allMaps = MapConfig.loadAll()
            let availableDropPointIds = Set(allMaps.compactMap { $0.dropPointId })
            let filteredDropPoints = dropPoints.filter { availableDropPointIds.contains($0.id) }

            print("[DropPointLoader] Filtered to \(filteredDropPoints.count) drop points with maps")

            cachedDropPoints = filteredDropPoints.sorted { $0.id < $1.id }
            return cachedDropPoints!
        } catch {
            print("[DropPointLoader] ERROR: Failed to load droppoints.json: \(error)")
            return loadDropPointsFromMaps() // Fallback
        }
    }

    /// Fallback: Loads drop points by inferring from available maps
    private static func loadDropPointsFromMaps() -> [DropPoint] {
        let allMaps = MapConfig.loadAll()
        let uniqueDropPointIds = Set(allMaps.compactMap { $0.dropPointId })

        let dropPoints = uniqueDropPointIds.sorted().map { id in
            DropPoint(id: id, name: "Drop Point \(id)", nameEn: nil)
        }
        cachedDropPoints = dropPoints
        return dropPoints
    }

    /// Filters maps based on a selected drop point ID.
    static func getMaps(forDropPointId dropPointId: Int?) -> [MapConfig] {
        let allMaps = MapConfig.loadAll()
        if let dropPointId = dropPointId {
            return allMaps.filter { $0.dropPointId == dropPointId }
        } else {
            return allMaps // If no drop point is selected, return all maps
        }
    }
}
