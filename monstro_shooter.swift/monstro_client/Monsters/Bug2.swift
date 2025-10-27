import Foundation
import SpriteKit

/// Bug2: Monster Type ID 4
/// Faster bug variant with higher damage
class Bug2: Monster {
    static let monsterTypeID = 4

    override init() {
        super.init()

        // Stats from database for Monster ID 4
        speed = 1.8 * 100.0
        boxSize = CGSize(width: 44, height: 44)
        damage = 5.0
        health = 4.0
        hitCooldown = 0.3
        rotationOffset = .pi / 8

        // Animation configuration
        walkAnimationDirectory = "monsters/bug2/walk"
        dyingAnimationDirectory = "monsters/bug2/dying"
        walkFrameRate = 0.08
        dyingFrameRate = 0.06

        // Sound configuration
        deathSounds = ["monster_bug_1.wav", "monster_bug_2.wav"]
    }
}
