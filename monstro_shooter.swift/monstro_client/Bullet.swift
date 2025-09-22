import Foundation
import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Lightweight wrapper for bullet nodes and creation utility.
class Bullet {
    let sprite: SKSpriteNode

    init(sprite: SKSpriteNode) {
        self.sprite = sprite
    }

    /// Create bullet with optional texture (falls back to colored dot).
    static func create(at position: CGPoint, velocity: CGVector, weaponsImageName: String? = "weapons.png") -> Bullet {
        // Try to load bullet texture from weapons spritesheet
        var bulletNode: SKSpriteNode
        if let name = weaponsImageName,
           let path = Bundle.main.path(forResource: name.replacingOccurrences(of: ".png", with: ""), ofType: "png") {
            #if os(macOS)
            if let nsImage = NSImage(contentsOfFile: path) {
                let texture = SKTexture(image: nsImage)
                bulletNode = SKSpriteNode(texture: texture)
                bulletNode.size = CGSize(width: 8, height: 8)
            } else {
                bulletNode = SKSpriteNode(color: .yellow, size: CGSize(width: 6, height: 6))
            }
            #else
            if let uiImage = UIImage(contentsOfFile: path) {
                let texture = SKTexture(image: uiImage)
                bulletNode = SKSpriteNode(texture: texture)
                bulletNode.size = CGSize(width: 8, height: 8)
            } else {
                bulletNode = SKSpriteNode(color: .yellow, size: CGSize(width: 6, height: 6))
            }
            #endif
        } else {
            bulletNode = SKSpriteNode(color: .yellow, size: CGSize(width: 6, height: 6))
        }

        bulletNode.position = position
        bulletNode.name = "bullet"
        bulletNode.zPosition = 5

        bulletNode.physicsBody = SKPhysicsBody(circleOfRadius: bulletNode.size.width/2)
        bulletNode.physicsBody?.categoryBitMask = PhysicsCategory.bullet
        bulletNode.physicsBody?.contactTestBitMask = PhysicsCategory.monster
        bulletNode.physicsBody?.collisionBitMask = 0
        bulletNode.physicsBody?.affectedByGravity = false
        bulletNode.physicsBody?.velocity = velocity

        // Auto-remove after time to avoid leaks (the scene/update loop may also clean up)
        let removeAction = SKAction.sequence([
            SKAction.wait(forDuration: 3.0),
            SKAction.removeFromParent()
        ])
        bulletNode.run(removeAction)

        return Bullet(sprite: bulletNode)
    }
}
