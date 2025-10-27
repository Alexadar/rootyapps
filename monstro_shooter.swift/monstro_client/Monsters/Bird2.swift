import Foundation
import SpriteKit

/// Bird2 (Beetle2): Monster Type ID 5
/// Faster flying variant with higher damage
class Bird2: Monster {
    static let monsterTypeID = 5

    override init() {
        super.init()

        // Stats from database for Monster ID 5
        speed = 2.3 * 100.0
        boxSize = CGSize(width: 50, height: 50)
        damage = 5.0
        health = 6.0
        hitCooldown = 0.3
        rotationOffset = .pi / 8

        // Animation configuration
        walkAnimationDirectory = "monsters/bird2/walk"
        dyingAnimationDirectory = "monsters/bird2/dying"
        walkFrameRate = 0.08
        dyingFrameRate = 0.06

        // Sound configuration
        deathSounds = ["monster_avia_1.wav", "monster_avia_2.wav"]
    }
}
