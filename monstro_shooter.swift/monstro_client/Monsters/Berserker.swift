import Foundation
import SpriteKit

/// Berserker (Walker/Beetle1): Monster Type ID 2
/// Basic walker monster with melee attack
class Berserker: Monster {
    static let monsterTypeID = 2

    override init() {
        super.init()

        // Stats from database for Monster ID 2
        speed = 0.94 * 100.0
        boxSize = CGSize(width: 60, height: 60)
        damage = 4.0
        health = 10.0
        hitCooldown = 0.5
        rotationOffset = .pi / 8

        // Animation configuration
        walkAnimationDirectory = "monsters/berserker/walk"
        dyingAnimationDirectory = "monsters/berserker/dying"
        walkFrameRate = 0.08
        dyingFrameRate = 0.06

        // Sound configuration
        deathSounds = ["monster_walker_1.wav", "monster_walker_2.wav"]
    }
}
