import Foundation
import SpriteKit

/// Bug: Monster Type ID 1
/// Fast, low-health melee attacker
class Bug: Monster {
    static let monsterTypeID = 1

    override init() {
        super.init()

        // Stats from database for Monster ID 1
        speed = 1.5 * 100.0
        boxSize = CGSize(width: 44, height: 44)
        damage = 2.0
        health = 4.0
        hitCooldown = 0.3
        rotationOffset = .pi / 8

        // Animation configuration
        walkAnimationDirectory = "monsters/bug/walk"
        dyingAnimationDirectory = "monsters/bug/dying"
        walkFrameRate = 0.08
        dyingFrameRate = 0.06

        // Sound configuration
        deathSounds = ["monster_bug_1.wav", "monster_bug_2.wav"]
    }
}
