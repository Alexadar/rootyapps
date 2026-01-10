import Foundation
import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Monster base class with generalized animation support
class Monster {
    var sprite: SKSpriteNode!
    var monsterTypeID: Int = 0  // Type ID for serialization
    var speed: CGFloat = GameConstants.monsterSpeed
    var boxSize: CGSize = GameConstants.monsterBoxSize
    var rotationOffset: CGFloat = GameConstants.monsterRotationOffset
    var isDead: Bool = false
    var damage: CGFloat = 5.0
    var health: CGFloat = 10.0
    var lastHitTime: TimeInterval = 0
    var hitCooldown: TimeInterval = 1.0

    // Steering behavior (from old game)
    var velocityX: CGFloat = 0
    var velocityY: CGFloat = 0
    var turnRate: CGFloat = 34  // Steering speed (for flying monsters with arcs)
    var useDirectSteering: Bool = false  // true = instant steering (bugs/walkers), false = arc steering (birds)

    // Animation system
    private var walkFrames: [SKTexture] = []
    private var dyingFrames: [SKTexture] = []
    public var isDying = false
    private var animationTimer: TimeInterval = 0

    // Animation configuration (set in subclass init)
    var walkAnimationDirectory: String? = nil
    var dyingAnimationDirectory: String? = nil
    var walkFrameRate: TimeInterval = 0.08
    var dyingFrameRate: TimeInterval = 0.06

    // Sound files (set in subclass init)
    var deathSounds: [String] = []

    init() {}

    /// Initialize from config
    convenience init(config: MonsterConfig) {
        self.init()

        speed = config.speed
        boxSize = config.boxSize
        damage = config.damage
        health = config.health
        hitCooldown = config.hitCooldown
        rotationOffset = config.rotationOffset
        useDirectSteering = config.useDirectSteering

        walkAnimationDirectory = config.walkAnimationDirectory
        dyingAnimationDirectory = config.dyingAnimationDirectory
        walkFrameRate = config.walkFrameRate
        dyingFrameRate = config.dyingFrameRate

        deathSounds = config.deathSounds
    }

    /// Setup with texture loading from configured directories
    func setup(at position: CGPoint, targetPosition: CGPoint) {
        // Load animation frames if directories configured
        if let walkDir = walkAnimationDirectory {
            walkFrames = loadTextures(fromDirectory: walkDir)
        }
        if let dyingDir = dyingAnimationDirectory {
            dyingFrames = loadTextures(fromDirectory: dyingDir)
        }

        // Create sprite with first walk frame or fallback color
        if let first = walkFrames.first {
            sprite = SKSpriteNode(texture: first, size: boxSize)
        } else {
            sprite = SKSpriteNode(color: SKColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0), size: boxSize)
        }

        sprite.position = position
        sprite.zPosition = 8
        sprite.name = "monster"

        sprite.physicsBody = SKPhysicsBody(rectangleOf: boxSize)
        sprite.physicsBody?.categoryBitMask = PhysicsCategory.monster
        sprite.physicsBody?.contactTestBitMask = PhysicsCategory.bullet | PhysicsCategory.player
        sprite.physicsBody?.collisionBitMask = 0
        sprite.physicsBody?.affectedByGravity = false

        // Start walk animation if available
        if !walkFrames.isEmpty {
            let walkAnim = SKAction.animate(with: walkFrames, timePerFrame: walkFrameRate, resize: true, restore: false)
            sprite.run(SKAction.repeatForever(walkAnim), withKey: "walk")
        }
    }

    /// Update monster movement and animation
    func update(deltaTime: TimeInterval, playerPosition: CGPoint, playerHitboxRadius: CGFloat) {
        guard !isDying else { return }

        let dx = playerPosition.x - sprite.position.x
        let dy = playerPosition.y - sprite.position.y
        let distance = sqrt(dx*dx + dy*dy)

        let stopDistance = playerHitboxRadius + (boxSize.width / 2.0)

        if distance > stopDistance {
            if useDirectSteering {
                // Direct steering (bugs, walkers) - move straight to target
                let dirX = dx / distance
                let dirY = dy / distance

                velocityX = dirX * speed
                velocityY = dirY * speed

                sprite.position.x += velocityX * CGFloat(deltaTime)
                sprite.position.y += velocityY * CGFloat(deltaTime)

                let angle = atan2(velocityY, velocityX)
                sprite.zRotation = angle + rotationOffset
            } else {
                // Arc steering (birds) - smooth turning with momentum
                let distanceTotal = distance

                // Steering toward target
                let moveDistanceX = turnRate * dx / distanceTotal
                let moveDistanceY = turnRate * dy / distanceTotal

                velocityX += moveDistanceX * CGFloat(deltaTime)
                velocityY += moveDistanceY * CGFloat(deltaTime)

                // Normalize velocity and apply speed
                let totalVelocity = sqrt(velocityX*velocityX + velocityY*velocityY)
                if totalVelocity > 0 {
                    velocityX = speed * velocityX / totalVelocity
                    velocityY = speed * velocityY / totalVelocity
                }

                sprite.position.x += velocityX * CGFloat(deltaTime)
                sprite.position.y += velocityY * CGFloat(deltaTime)

                let angle = atan2(velocityY, velocityX)
                sprite.zRotation = angle + rotationOffset
            }
        }

        sprite.size = boxSize
        animationTimer += deltaTime
    }

    /// Handle death with animation
    func die() {
        guard !isDying else { return }
        isDying = true
        isDead = true

        // Play death sound
        playDeathSound()

        // Stop walk animation
        sprite.removeAction(forKey: "walk")

        // Play dying animation (keyed to prevent stacking if die() called multiple times)
        if !dyingFrames.isEmpty {
            sprite.removeAction(forKey: "dying")
            let dyingAnim = SKAction.animate(with: dyingFrames, timePerFrame: dyingFrameRate, resize: true, restore: false)
            sprite.run(dyingAnim, withKey: "dying")  // key prevents animation stacking
        } else {
            // Fallback: tint and freeze
            let tint = SKAction.colorize(with: .red, colorBlendFactor: 0.6, duration: 0.12)
            sprite.run(tint)
        }

        // Completely remove physics body to prevent any further collisions
        sprite.physicsBody = nil
    }

    /// Play appropriate death sound
    private func playDeathSound() {
        guard !deathSounds.isEmpty else { return }
        AudioManager.shared.playRandomSound(from: deathSounds)
    }
}
