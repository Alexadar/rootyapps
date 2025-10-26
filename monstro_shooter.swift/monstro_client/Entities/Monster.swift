import Foundation
import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Monster base class (moved out of GameScene for separation of concerns).
class Monster {
    var sprite: SKSpriteNode!
    var speed: CGFloat = GameConstants.monsterSpeed
    var boxSize: CGSize = GameConstants.monsterBoxSize
    var rotationOffset: CGFloat = GameConstants.monsterRotationOffset
    var isDead: Bool = false
    var damage: Int = 5  // Default damage per hit
    var lastHitTime: TimeInterval = 0  // Track last hit to prevent rapid hits
    var hitCooldown: TimeInterval = 1.0  // Seconds between hits
    private var animationTimer: TimeInterval = 0

    init() {}

    /// Default setup: simple colored placeholder (kept for safety)
    func setup(at position: CGPoint, targetPosition: CGPoint) {
        sprite = SKSpriteNode(color: SKColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0), size: boxSize)
        sprite.position = position
        sprite.zPosition = 8
        sprite.name = "monster"

        sprite.physicsBody = SKPhysicsBody(rectangleOf: boxSize)
        sprite.physicsBody?.categoryBitMask = PhysicsCategory.monster
        sprite.physicsBody?.contactTestBitMask = PhysicsCategory.bullet | PhysicsCategory.player
        sprite.physicsBody?.collisionBitMask = 0
        sprite.physicsBody?.affectedByGravity = false
    }

    /// Default movement: move toward player and rotate (override in subclasses if needed).
    /// Stops at player hitbox edge to prevent flickering
    func update(deltaTime: TimeInterval, playerPosition: CGPoint, playerHitboxRadius: CGFloat) {
        let dx = playerPosition.x - sprite.position.x
        let dy = playerPosition.y - sprite.position.y
        let distance = sqrt(dx*dx + dy*dy)

        // Stop distance is player hitbox radius + half of monster size
        let stopDistance = playerHitboxRadius + (boxSize.width / 2.0)

        if distance > stopDistance {
            let ndx = dx / distance
            let ndy = dy / distance

            sprite.position.x += ndx * speed * CGFloat(deltaTime)
            sprite.position.y += ndy * speed * CGFloat(deltaTime)

            // For top-down art that expects left-right movement, rotate so sprite faces movement
            let angle = atan2(dy, dx)
            sprite.zRotation = angle + rotationOffset
        }

        // Ensure sprite size matches box at runtime
        sprite.size = boxSize

        animationTimer += deltaTime
    }

    /// Default die: no-op for generic monsters. Subclasses should override to provide death animation
    /// behavior. The base implementation removes the sprite to avoid leaving unknown nodes in scene.
    func die() {
        isDead = true
        sprite.removeAllActions()
        sprite.physicsBody = nil
        sprite.removeFromParent()
    }
}
