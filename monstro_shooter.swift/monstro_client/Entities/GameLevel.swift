import Foundation
import CoreGraphics

// MARK: - Game Level Configuration
/// Represents a playable level/map with time-based wave spawning system
/// Based on the old .NET server Map entity structure
struct GameLevel: Codable, Identifiable {

    // MARK: - Basic Properties
    let id: Int
    let name: String
    let description: String
    let orderNumber: Int              // Level progression order
    let difficulty: Int               // 1-10 difficulty scale

    // MARK: - Requirements & Costs
    let levelRequirement: Int         // Player level required to unlock
    let energyCost: Int               // Energy to play
    let moneyCost: Int                // Soft currency cost
    let hardMoneyCost: Int            // Premium currency cost

    // MARK: - Gameplay Settings
    let duration: TimeInterval        // Total level duration in seconds

    // CHANGED: Two-level map system
    // 1. mapSize = Fixed map boundaries (player can't go beyond this)
    // 2. spawnBoxSize = Dynamic box around player where monsters spawn from edges
    //
    // Behavior:
    // - Player normally at center of spawn box
    // - Spawn box follows player as they move
    // - When player reaches map edge, they stop at the corner/edge
    // - Spawn box continues to extend beyond map boundaries
    // - Monsters spawn from spawn box edges (even if outside map)
    // Example: Map 4500x4500, SpawnBox 1500x1500
    let mapSize: CGSize               // Fixed map boundaries (e.g., 4500x4500 or 12000x12000)
    let spawnBoxSize: CGSize          // Dynamic spawn box around player (e.g., 1500x1500)
    let backgroundResource: String    // Background image asset name (tiled if needed)

    // MARK: - Wave System
    /// Time-based spawn configuration - monsters spawn in waves over time
    let spawnWaves: [SpawnWave]

    // MARK: - Spawn Points
    /// Specific locations where monsters can spawn (optional, defaults to edges)
    let spawnPoints: [SpawnPoint]?

    // MARK: - Rewards
    let experienceReward: Int
    let moneyReward: Int

    // MARK: - Progression
    let nextLevelId: Int?             // Linked list progression
    let previousLevelId: Int?

    // MARK: - Default Initializer
    init(
        id: Int,
        name: String,
        description: String = "",
        orderNumber: Int,
        difficulty: Int,
        levelRequirement: Int = 1,
        energyCost: Int = 0,
        moneyCost: Int = 0,
        hardMoneyCost: Int = 0,
        duration: TimeInterval = 180,
        mapSize: CGSize = CGSize(width: 4500, height: 4500),        // Default: 4500x4500 map
        spawnBoxSize: CGSize = GameConstants.defaultSpawnBoxSize,   // Spawn box from constants
        backgroundResource: String = "map_background",
        spawnWaves: [SpawnWave],
        spawnPoints: [SpawnPoint]? = nil,
        experienceReward: Int = 100,
        moneyReward: Int = 50,
        nextLevelId: Int? = nil,
        previousLevelId: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.orderNumber = orderNumber
        self.difficulty = difficulty
        self.levelRequirement = levelRequirement
        self.energyCost = energyCost
        self.moneyCost = moneyCost
        self.hardMoneyCost = hardMoneyCost
        self.duration = duration
        self.mapSize = mapSize
        self.spawnBoxSize = spawnBoxSize
        self.backgroundResource = backgroundResource
        self.spawnWaves = spawnWaves
        self.spawnPoints = spawnPoints
        self.experienceReward = experienceReward
        self.moneyReward = moneyReward
        self.nextLevelId = nextLevelId
        self.previousLevelId = previousLevelId
    }
}

// MARK: - Spawn Wave
/// Time-based spawn configuration matching old server's MonstersCountPeriod + MonstersTypesPeriod
struct SpawnWave: Codable {
    let startTime: TimeInterval       // When this wave starts (seconds from level start)
    let monsterCount: Int             // How many monsters to spawn in this wave
    let monsterTypes: [String]        // Monster type names (e.g., ["Berserker", "Zombie"])
    let spawnInterval: TimeInterval   // Time between individual monster spawns (default 1.0)

    init(startTime: TimeInterval, monsterCount: Int, monsterTypes: [String], spawnInterval: TimeInterval = 1.0) {
        self.startTime = startTime
        self.monsterCount = monsterCount
        self.monsterTypes = monsterTypes
        self.spawnInterval = spawnInterval
    }
}

// MARK: - Spawn Point
/// Specific spawn location matching old server's MapSpawnPoint
struct SpawnPoint: Codable {
    let x: CGFloat
    let y: CGFloat

    var position: CGPoint {
        return CGPoint(x: x, y: y)
    }

    init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    init(position: CGPoint) {
        self.x = position.x
        self.y = position.y
    }
}

// MARK: - Level Manager
/// Manages level loading, progression, and current level state
class LevelManager {
    static let shared = LevelManager()

    private(set) var levels: [GameLevel] = []
    private(set) var currentLevel: GameLevel?

    private init() {
        loadLevels()
    }

    /// Load levels from JSON configuration file or use hardcoded defaults
    func loadLevels() {
        // Try to load from JSON first
        if let loadedLevels = loadLevelsFromJSON() {
            levels = loadedLevels
        } else {
            // Fallback to default hardcoded levels
            levels = createDefaultLevels()
        }
    }

    /// Load levels from JSON file in bundle
    private func loadLevelsFromJSON() -> [GameLevel]? {
        guard let url = Bundle.main.url(forResource: "levels", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let levels = try? JSONDecoder().decode([GameLevel].self, from: data) else {
            return nil
        }
        return levels
    }

    /// Create default hardcoded levels for initial development
    private func createDefaultLevels() -> [GameLevel] {
        return [
            // Test Level - 20 waves escalating to 200 monsters
            GameLevel(
                id: 1,
                name: "Test level",
                description: "Testing level with 20 waves",
                orderNumber: 1,
                difficulty: 5,
                levelRequirement: 1,
                duration: 600,  // 10 minutes
                mapSize: CGSize(width: 12000, height: 12000),     // Large map
                spawnBoxSize: GameConstants.defaultSpawnBoxSize,  // 4500x4500 spawn box
                spawnWaves: [
                    SpawnWave(startTime: 0, monsterCount: 5, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 20, monsterCount: 8, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 40, monsterCount: 12, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 60, monsterCount: 15, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 80, monsterCount: 20, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 100, monsterCount: 25, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 120, monsterCount: 30, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 140, monsterCount: 35, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 160, monsterCount: 40, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 180, monsterCount: 50, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 210, monsterCount: 60, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 240, monsterCount: 70, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 270, monsterCount: 80, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 300, monsterCount: 90, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 330, monsterCount: 100, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 360, monsterCount: 110, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 390, monsterCount: 120, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 420, monsterCount: 140, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 450, monsterCount: 160, monsterTypes: ["Berserker"]),
                    SpawnWave(startTime: 480, monsterCount: 200, monsterTypes: ["Berserker"], spawnInterval: 0.5)
                ],
                experienceReward: 1000,
                moneyReward: 500
            )
        ]
    }

    /// Start playing a specific level
    func startLevel(levelId: Int) -> GameLevel? {
        currentLevel = levels.first { $0.id == levelId }
        return currentLevel
    }

    /// Get next level in progression
    func getNextLevel() -> GameLevel? {
        guard let current = currentLevel, let nextId = current.nextLevelId else { return nil }
        return levels.first { $0.id == nextId }
    }

    /// Get level by ID
    func getLevel(id: Int) -> GameLevel? {
        return levels.first { $0.id == id }
    }
}
