import Foundation
import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Enhanced bullet class with weapon system support
class Bullet {
    let sprite: SKSpriteNode
    let info: BulletInfo

    var hitCount: Int = 0
    var distanceTraveled: CGFloat = 0
    let startPosition: CGPoint
    var currentScale: CGFloat

    init(sprite: SKSpriteNode, info: BulletInfo, startPosition: CGPoint) {
        self.sprite = sprite
        self.info = info
        self.startPosition = startPosition
        self.currentScale = info.startScale
    }

    /// Check if bullet can penetrate another enemy
    func canPenetrate() -> Bool {
        hitCount += 1
        return hitCount <= info.penetration
    }

    /// Check if bullet should be removed
    func isExpired() -> Bool {
        return hitCount >= info.penetration || distanceTraveled >= info.range
    }

    /// Update bullet (scale growth and distance tracking)
    func update(deltaTime: TimeInterval) {
        // Grow bullet
        if currentScale < info.maxScale {
            currentScale += info.scaleGrowth
            sprite.setScale(currentScale)
        }

        // Track distance
        let velocity = sprite.physicsBody?.velocity ?? CGVector.zero
        let movement = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy) * CGFloat(deltaTime)
        distanceTraveled += movement
    }

    /// Create bullet from weapon system
    static func create(at position: CGPoint, angle: CGFloat, bulletInfo: BulletInfo) -> Bullet {
        // Angle already includes deviation from GameScene, use directly

        // Try to load bullet texture
        var bulletNode: SKSpriteNode
        if let path = Bundle.main.path(forResource: "weapons", ofType: "png") {
            #if os(macOS)
            if let nsImage = NSImage(contentsOfFile: path) {
                let texture = SKTexture(image: nsImage)
                bulletNode = SKSpriteNode(texture: texture)
                bulletNode.size = CGSize(width: 12, height: 12)
            } else {
                bulletNode = SKSpriteNode(color: .yellow, size: CGSize(width: 10, height: 10))
            }
            #else
            if let uiImage = UIImage(contentsOfFile: path) {
                let texture = SKTexture(image: uiImage)
                bulletNode = SKSpriteNode(texture: texture)
                bulletNode.size = CGSize(width: 12, height: 12)
            } else {
                bulletNode = SKSpriteNode(color: .yellow, size: CGSize(width: 10, height: 10))
            }
            #endif
        } else {
            bulletNode = SKSpriteNode(color: .yellow, size: CGSize(width: 10, height: 10))
        }

        bulletNode.position = position
        bulletNode.name = "bullet"
        bulletNode.zPosition = 5
        bulletNode.setScale(bulletInfo.startScale)

        // Set rotation to match direction
        bulletNode.zRotation = angle

        // Setup physics
        bulletNode.physicsBody = SKPhysicsBody(circleOfRadius: bulletNode.size.width/2)
        bulletNode.physicsBody?.categoryBitMask = PhysicsCategory.bullet
        bulletNode.physicsBody?.contactTestBitMask = PhysicsCategory.monster
        bulletNode.physicsBody?.collisionBitMask = 0
        bulletNode.physicsBody?.affectedByGravity = false
        bulletNode.physicsBody?.isDynamic = true
        bulletNode.physicsBody?.usesPreciseCollisionDetection = true

        // Calculate velocity from angle and speed
        let velocity = CGVector(
            dx: cos(angle) * bulletInfo.speed,
            dy: sin(angle) * bulletInfo.speed
        )
        bulletNode.physicsBody?.velocity = velocity

        return Bullet(sprite: bulletNode, info: bulletInfo, startPosition: position)
    }

    /// Legacy create method for compatibility
    static func create(at position: CGPoint, velocity: CGVector, weaponsImageName: String? = "weapons.png") -> Bullet {
        // Create with default bullet info
        let angle = atan2(velocity.dy, velocity.dx)
        let speed = sqrt(velocity.dx * velocity.dx + velocity.dy * velocity.dy)

        let defaultInfo = BulletInfo(
            damage: 10,
            speed: speed,
            range: 2000,
            deviation: 0,
            penetration: 1,
            startScale: 1.0,
            maxScale: 1.0,
            scaleGrowth: 0,
            textureName: "bullet_pistol"
        )

        return create(at: position, angle: angle, bulletInfo: defaultInfo)
    }
}
