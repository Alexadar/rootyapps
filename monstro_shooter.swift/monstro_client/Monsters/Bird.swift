import Foundation
import SpriteKit

/// Bird (Beetle): Monster Type ID 3
/// Flying monster with moderate speed
class Bird: Monster {
    static let monsterTypeID = 3

    override init() {
        super.init()

        // Stats from database for Monster ID 3
        speed = 2.1 * 100.0
        boxSize = CGSize(width: 50, height: 50)
        damage = 2.0
        health = 6.0
        hitCooldown = 0.3
        rotationOffset = .pi / 8

        // Animation configuration
        walkAnimationDirectory = "monsters/bird/walk"
        dyingAnimationDirectory = "monsters/bird/dying"
        walkFrameRate = 0.08
        dyingFrameRate = 0.06

        // Sound configuration
        deathSounds = ["monster_avia_1.wav", "monster_avia_2.wav"]
    }
}
