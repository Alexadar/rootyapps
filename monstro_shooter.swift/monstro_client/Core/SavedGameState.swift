import Foundation
import CoreGraphics
import QuartzCore
import SpriteKit

/// Saved game state for persistence across app lifecycle
struct SavedGameState: Codable {
    // Level identifier
    let mapFilename: String

    // Timing (elapsed time, not absolute)
    let elapsedTime: TimeInterval
    let lastDamageElapsed: TimeInterval

    // Player state
    let playerPosition: CodablePoint
    let playerHealth: Int
    let playerMaxHealth: Int
    let playerAmmo: Int

    // Wave state
    let currentWaveIndex: Int
    let spawnedWaveIndices: [Int]
    let killCount: Int

    // Active monsters (lightweight)
    let monsters: [SavedMonster]

    // Tutorial state
    let tutorialMoveShown: Bool
    let tutorialShootShown: Bool
    let tutorialKillShown: Bool

    // Timestamp for validation
    let savedAt: Date
}

/// Lightweight monster data for serialization
struct SavedMonster: Codable {
    let typeID: Int
    let position: CodablePoint
    let health: Double
    let isDead: Bool
}

/// Codable wrapper for CGPoint
struct CodablePoint: Codable {
    let x: CGFloat
    let y: CGFloat

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

// MARK: - GameScene State Persistence Extension
extension GameScene {

    private static let savedGameKey = "SavedGameState"

    /// Save current game state to UserDefaults
    func saveGameState() {
        guard !isGameOver,
              let player = playerEntity,
              let level = currentLevel else { return }

        // Calculate elapsed times
        let currentTime = CACurrentMediaTime()
        let elapsed = levelStartTime > 0 ? currentTime - levelStartTime : 0
        let damageElapsed = lastDamageTime > 0 ? currentTime - lastDamageTime : 0

        // Serialize monsters
        let savedMonsters = monsters.map { monster in
            SavedMonster(
                typeID: monster.monsterTypeID,
                position: CodablePoint(monster.sprite.position),
                health: Double(monster.health),
                isDead: monster.isDead
            )
        }

        // Get tutorial state
        let tutorialState = tutorialController?.getState() ?? (false, false, false)

        let state = SavedGameState(
            mapFilename: SettingsManager.shared.selectedMapFilename,
            elapsedTime: elapsed,
            lastDamageElapsed: damageElapsed,
            playerPosition: CodablePoint(player.sprite.position),
            playerHealth: player.health,
            playerMaxHealth: player.maxHealth,
            playerAmmo: player.currentWeapon.currentAmmo,
            currentWaveIndex: currentWaveIndex,
            spawnedWaveIndices: Array(spawnedWaves),
            killCount: killCount,
            monsters: savedMonsters,
            tutorialMoveShown: tutorialState.0,
            tutorialShootShown: tutorialState.1,
            tutorialKillShown: tutorialState.2,
            savedAt: Date()
        )

        // Encode and save
        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: GameScene.savedGameKey)
        }
    }

    /// Restore game state from UserDefaults
    /// Returns true if state was restored successfully
    @discardableResult
    func restoreGameState() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: GameScene.savedGameKey),
              let state = try? JSONDecoder().decode(SavedGameState.self, from: data) else {
            return false
        }

        // Validate saved state isn't too old (max 1 hour)
        let maxAge: TimeInterval = 3600
        guard Date().timeIntervalSince(state.savedAt) < maxAge else {
            clearSavedGameState()
            return false
        }

        // Validate map matches
        let currentMap = SettingsManager.shared.selectedMapFilename
        guard state.mapFilename == currentMap || state.mapFilename == currentLevel?.name else {
            clearSavedGameState()
            return false
        }

        // Restore player state
        if let player = playerEntity {
            player.sprite.position = state.playerPosition.cgPoint
            player.health = state.playerHealth
            player.maxHealth = state.playerMaxHealth
            player.currentWeapon.restoreAmmo(state.playerAmmo)
        }

        // Restore timing (relative to current time)
        let currentTime = CACurrentMediaTime()
        levelStartTime = currentTime - state.elapsedTime
        lastDamageTime = state.lastDamageElapsed > 0 ? currentTime - state.lastDamageElapsed : 0

        // Restore wave state
        currentWaveIndex = state.currentWaveIndex
        spawnedWaves = Set(state.spawnedWaveIndices)
        killCount = state.killCount

        // Clear existing monsters
        for monster in monsters {
            monster.sprite.removeFromParent()
        }
        monsters.removeAll()

        // Restore monsters
        for savedMonster in state.monsters where !savedMonster.isDead {
            guard let config = MonsterRegistry.shared.getConfig(forID: savedMonster.typeID) else { continue }

            let monster = Monster(config: config)
            monster.monsterTypeID = savedMonster.typeID
            monster.health = CGFloat(savedMonster.health)

            if let player = playerEntity {
                monster.setup(at: savedMonster.position.cgPoint, targetPosition: player.sprite.position)
            }

            renderer?.world.worldLayer.addChild(monster.sprite)
            monsters.append(monster)
        }

        // Restore tutorial state
        tutorialController?.restoreState(
            moveShown: state.tutorialMoveShown,
            shootShown: state.tutorialShootShown,
            killShown: state.tutorialKillShown
        )

        // Clear saved state after successful restore
        clearSavedGameState()

        return true
    }

    /// Clear saved game state
    func clearSavedGameState() {
        UserDefaults.standard.removeObject(forKey: GameScene.savedGameKey)
    }

    /// Check if there's a saved game state
    static func hasSavedGameState() -> Bool {
        UserDefaults.standard.data(forKey: savedGameKey) != nil
    }
}
