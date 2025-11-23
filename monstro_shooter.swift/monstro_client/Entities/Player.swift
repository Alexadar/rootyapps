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

        // Calculate minimum damage (0.4 every 4th hit to prevent zero damage)
        let minDamage = (hitCount % 4 == 0) ? 0.4 : 0.0

        // Apply armor formula from old game
        let actualDamage = max(damage - defense, minDamage)

        health -= Int(actualDamage)
        if health < 0 { health = 0 }

        print("[Player] Took \(Int(actualDamage)) damage (from \(Int(damage)), defense: \(defense)). Health: \(health)/\(maxHealth)")
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
        var mv = movement
        // Already expected to be normalized or in range -1..1; guard division by zero
        let length = sqrt(mv.dx * mv.dx + mv.dy * mv.dy)
        if length > 0 {
            mv.dx /= length
            mv.dy /= length

            // Match old game's 0.75 diagonal multiplier (not normalized 0.707)
            let isDiagonal = abs(mv.dx) > 0.1 && abs(mv.dy) > 0.1
            let multiplier: CGFloat = isDiagonal ? 0.75 : 1.0

            let newX = sprite.position.x + mv.dx * speed * multiplier * CGFloat(deltaTime)
            let newY = sprite.position.y + mv.dy * speed * multiplier * CGFloat(deltaTime)

            // Keep player within map bounds (not viewport bounds).
            // Scene uses center anchor point (0.5, 0.5), so map coordinates are -mapSize/2 to +mapSize/2
            let halfWidth = sprite.size.width / 2
            let halfHeight = sprite.size.height / 2

            let minX = -mapSize.width / 2 + halfWidth
            let maxX = mapSize.width / 2 - halfWidth
            let minY = -mapSize.height / 2 + halfHeight
            let maxY = mapSize.height / 2 - halfHeight

            sprite.position.x = max(minX, min(maxX, newX))
            sprite.position.y = max(minY, min(maxY, newY))
        }
    }
}
