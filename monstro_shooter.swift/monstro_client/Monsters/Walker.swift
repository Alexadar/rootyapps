import Foundation
import SpriteKit

/// Walker: Monster Type ID 23
/// Slow, heavy ground unit (base walker without upgrades)
class Walker: Monster {
    static let monsterTypeID = 23

    override init() {
        super.init()

        // Stats from database for Monster ID 23
        speed = 0.6 * 100.0
        boxSize = CGSize(width: 60, height: 60)
        damage = 4.0
        health = 10.0
        hitCooldown = 0.5
        rotationOffset = .pi / 8

        // Animation configuration
        walkAnimationDirectory = "monsters/walker/walk"
        dyingAnimationDirectory = "monsters/walker/dying"
        walkFrameRate = 0.08
        dyingFrameRate = 0.06

        // Sound configuration
        deathSounds = ["monster_walker_1.wav", "monster_walker_2.wav"]
    }
}
