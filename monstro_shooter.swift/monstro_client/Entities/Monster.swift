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
    var speed: CGFloat = 100.0
    var boxSize: CGSize = CGSize(width: 28, height: 28)
    var rotationOffset: CGFloat = .pi / 4
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
    func update(deltaTime: TimeInterval, playerPosition: CGPoint) {
        let dx = playerPosition.x - sprite.position.x
        let dy = playerPosition.y - sprite.position.y
        let distance = sqrt(dx*dx + dy*dy)

        if distance > 0 {
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
        sprite.removeAllActions()
        sprite.physicsBody = nil
        sprite.removeFromParent()
    }
}
