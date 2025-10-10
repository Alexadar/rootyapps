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

    init?(initialPosition: CGPoint, size: CGSize = CGSize(width: 60, height: 60), atlasImage: String? = "exoskeletons_0.png", xmlPath: String? = "exoskeletons_0.xml") {
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

        // Setup player physics
        sprite.physicsBody = SKPhysicsBody(rectangleOf: sprite.size)
        sprite.physicsBody?.categoryBitMask = PhysicsCategory.player
        sprite.physicsBody?.contactTestBitMask = PhysicsCategory.monster
        sprite.physicsBody?.collisionBitMask = 0
        sprite.physicsBody?.affectedByGravity = false

        self.speed = 300.0
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
    func move(by movement: CGVector, deltaTime: TimeInterval, sceneSize: CGSize) {
        var mv = movement
        // Already expected to be normalized or in range -1..1; guard division by zero
        let length = sqrt(mv.dx * mv.dx + mv.dy * mv.dy)
        if length > 0 {
            mv.dx /= length
            mv.dy /= length

            let newX = sprite.position.x + mv.dx * speed * CGFloat(deltaTime)
            let newY = sprite.position.y + mv.dy * speed * CGFloat(deltaTime)

            // Keep player within bounds.
            // Scene anchor may be center (0.5,0.5) or bottom-left (0,0). Compute scene origin from anchor,
            // then clamp using sceneSize so this method works for both coordinate systems.
            let halfWidth = sprite.size.width / 2
            let halfHeight = sprite.size.height / 2

            let anchorPoint = sprite.scene?.anchorPoint ?? CGPoint.zero
            let originX = -sceneSize.width * anchorPoint.x
            let originY = -sceneSize.height * anchorPoint.y

            let minX = originX + halfWidth
            let maxX = originX + sceneSize.width - halfWidth
            let minY = originY + halfHeight
            let maxY = originY + sceneSize.height - halfHeight

            sprite.position.x = max(minX, min(maxX, newX))
            sprite.position.y = max(minY, min(maxY, newY))
        }
    }
}
