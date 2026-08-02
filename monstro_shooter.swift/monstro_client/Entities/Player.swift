import Foundation
import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Wrapper around the player sprite and movement logic.
/// Provides a small API so GameScene doesn't manipulate raw SKSpriteNode internals everywhere.
class Player {
    let sprite: SKSpriteNode
    var speed: CGFloat
    var currentWeapon: Weapon
    var currentExoskeleton: ExoskeletonConfig
    var defense: Double  // Damage reduction (absolute value subtracted from incoming damage)
    var health: Int
    var maxHealth: Int
    var hitboxRadius: CGFloat  // Circular hitbox radius
    var hitCount: Int = 0  // Track hits for minimum damage calculation

    init?(initialPosition: CGPoint, size: CGSize = GameConstants.playerSize, atlasImage: String? = "exoskeletons_0.png", xmlPath: String? = "exoskeletons_0.xml") {
        // Try to load from atlas like previous implementation
        if let atlasImage = atlasImage,
           let xmlPath = xmlPath,
           let atlas = TextureAtlas(atlasImagePath: atlasImage, xmlPath: xmlPath),
           let bodyTexture = atlas.getTexture(named: "_0_exoskeleton0000") {
            sprite = SKSpriteNode(texture: bodyTexture)
            sprite.size = size
        } else {
            // Fallback visual
            sprite = SKSpriteNode(color: .green, size: CGSize(width: 40, height: 40))
        }

        sprite.position = initialPosition
        sprite.zPosition = 10
        sprite.name = "player"

        // Infer circular hitbox radius from sprite size (use average of width/height)
        self.hitboxRadius = (size.width + size.height) / 4.0

        // Setup player physics with circular body
        sprite.physicsBody = SKPhysicsBody(circleOfRadius: hitboxRadius)
        sprite.physicsBody?.categoryBitMask = PhysicsCategory.player
        sprite.physicsBody?.contactTestBitMask = PhysicsCategory.monster
        sprite.physicsBody?.collisionBitMask = 0
        sprite.physicsBody?.affectedByGravity = false

        // Initialize with default exoskeleton and weapon from managers
        guard let defaultExo = ExoskeletonManager.shared.getExoskeleton(id: 1),
              let defaultWeapon = WeaponManager.shared.getWeapon(id: 1) else {
            return nil
        }
        self.currentExoskeleton = defaultExo
        self.defense = currentExoskeleton.defence
        self.speed = GameConstants.playerSpeed * currentExoskeleton.speed
        self.currentWeapon = Weapon(config: defaultWeapon)
        self.maxHealth = 100
        self.health = 100
    }

    func getHealthPercentage() -> Int {
        return (health * 100) / maxHealth
    }

    /// Apply damage to player with armor calculation
    /// Based on old ActionScript formula: actualDamage = max(damage - defence, minDamage)
    func takeDamage(_ damage: Double) {
        hitCount += 1

        // Apply armor formula from old game (extracted to CombatMath for testability)
        let actualDamage = CombatMath.actualDamage(incoming: damage, defense: defense, hitCount: hitCount)

        health -= Int(actualDamage)
        if health < 0 { health = 0 }
    }

    /// Apply exoskeleton configuration to player
    func applyExoskeleton(_ exoskeleton: ExoskeletonConfig) {
        self.currentExoskeleton = exoskeleton
        self.defense = exoskeleton.defence
        self.speed = GameConstants.playerSpeed * exoskeleton.speed
        print("[Player] Applied exoskeleton: \(exoskeleton.name) (defense: \(defense), speed multiplier: \(exoskeleton.speed))")
    }

    func setPosition(_ p: CGPoint) {
        sprite.position = p
    }

    func position() -> CGPoint {
        return sprite.position
    }

    func aimToward(point: CGPoint) {
        let dx = point.x - sprite.position.x
        let dy = point.y - sprite.position.y
        let angle = atan2(dy, dx)
        sprite.zRotation = angle - (.pi / 2)
    }

    /// Move the player by a normalized movement vector scaled by speed and deltaTime.
    /// mapSize parameter defines the actual map boundaries (not viewport size)
    func move(by movement: CGVector, deltaTime: TimeInterval, mapSize: CGSize) {
        // Movement/clamping math lives in MovementMath so it can be unit-tested without a sprite.
        sprite.position = MovementMath.nextPosition(
            from: sprite.position,
            movement: movement,
            speed: speed,
            deltaTime: deltaTime,
            spriteSize: sprite.size,
            mapSize: mapSize
        )
    }
}
