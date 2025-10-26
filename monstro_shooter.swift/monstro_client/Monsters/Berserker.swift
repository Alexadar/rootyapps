import Foundation
import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Berserker: uses two animation groups: walk and dying.
/// Expects resources in bundle under:
///   monsters/berserker/walk/*.png
///   monsters/berserker/dying/*.png
class Berserker: Monster {
    private var walkFrames: [SKTexture] = []
    private var dyingFrames: [SKTexture] = []
    private var isDying = false

    override init() {
        super.init()
        // adjust default speed/box if needed
        speed = 100.0
        boxSize = CGSize(width: 40, height: 40)
        // rotate sprites so their front faces the player (90° CCW)
        rotationOffset = .pi / 8
        damage = 10  // Berserker damage per hit
        hitCooldown = 1.0  // 1 second between hits
    }

    override func setup(at position: CGPoint, targetPosition: CGPoint) {
        // Load frames (if available)
        walkFrames = loadTextures(fromDirectory: "monsters/berserker/walk")
        dyingFrames = loadTextures(fromDirectory: "monsters/berserker/dying")

        // Debug logging to verify resource discovery at runtime
        let exactWalkPaths = Bundle.main.paths(forResourcesOfType: "png", inDirectory: "monsters/berserker/walk")
        let exactDyingPaths = Bundle.main.paths(forResourcesOfType: "png", inDirectory: "monsters/berserker/dying")
        let rootPngs = Bundle.main.paths(forResourcesOfType: "png", inDirectory: nil)
        print("Berserker resource debug: exactWalk=\(exactWalkPaths.count), exactDying=\(exactDyingPaths.count), rootPngs=\(rootPngs.count)")
        if !exactWalkPaths.isEmpty { print("exactWalk sample: \((exactWalkPaths as NSArray).subarray(with: NSRange(location: 0, length: min(5, exactWalkPaths.count))) )") }
        if !exactDyingPaths.isEmpty { print("exactDying sample: \((exactDyingPaths as NSArray).subarray(with: NSRange(location: 0, length: min(5, exactDyingPaths.count))) )") }

        print("Loaded frames counts -> walkFrames:\(walkFrames.count) dyingFrames:\(dyingFrames.count)")

        // Use first walk frame as initial texture if available
        if let first = walkFrames.first {
            sprite = SKSpriteNode(texture: first, size: boxSize)
            } else {
            // fallback visual
            sprite = SKSpriteNode(color: SKColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 1.0), size: boxSize)
            print("Berserker: no walk frames found, using fallback colored sprite")
        }

        sprite.position = position
        sprite.zPosition = 8
        sprite.name = "monster"

        sprite.physicsBody = SKPhysicsBody(rectangleOf: boxSize)
        sprite.physicsBody?.categoryBitMask = PhysicsCategory.monster
        sprite.physicsBody?.contactTestBitMask = PhysicsCategory.bullet | PhysicsCategory.player
        sprite.physicsBody?.collisionBitMask = 0
        sprite.physicsBody?.affectedByGravity = false

        // Run walk animation if frames available
        if !walkFrames.isEmpty {
            // top-down sprites are usually drawn facing "up" — timePerFrame tuned to look smooth
            let walkAnim = SKAction.animate(with: walkFrames, timePerFrame: 0.08, resize: true, restore: false)
            sprite.run(SKAction.repeatForever(walkAnim), withKey: "walk")
        }

        print("Berserker setup complete: pos=\(position), size=\(boxSize), zPos=\(sprite.zPosition), hasTexture=\(sprite.texture != nil), parent=\(sprite.parent != nil)")
    }

    override func update(deltaTime: TimeInterval, playerPosition: CGPoint, playerHitboxRadius: CGFloat) {
        guard !isDying else { return }

        // Movement same as base but ensure sprite orientation and size
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

            // Because art is top-down, orient sprite so it visually matches movement:
            // rotate by angle and apply rotationOffset so the sprite's front faces the player.
            let angle = atan2(dy, dx)
            sprite.zRotation = angle + rotationOffset
        }

        // Keep sprite size equal to box size at runtime
        sprite.size = boxSize
    }

    /// Call to play dying animation once and keep last frame frozen on the field (no removal).
    override func die() {
        guard !isDying else { return }
        isDying = true
        isDead = true

        // Log entry for diagnostics
        print("Berserker.die() called. dyingFrames.count = \(dyingFrames.count)")

        // Play death sound
        AudioManager.shared.playWalkerSound()

        // Stop walking animation but keep current texture/orientation
        sprite.removeAction(forKey: "walk")

        // Ensure current texture is preserved before playing dying animation
        let priorTexture = sprite.texture

        // Play dying animation if available, then set last frame as static texture and stop actions.
        if !dyingFrames.isEmpty {
            print("Berserker: running dying animation with \(dyingFrames.count) frames")
            let dyingAnim = SKAction.animate(with: dyingFrames, timePerFrame: 0.06, resize: true, restore: false)
            sprite.run(dyingAnim) { [weak self] in
                guard let self = self else { return }
                // Set final frame texture and stop all actions so the sprite stays frozen.
                if let last = self.dyingFrames.last {
                    self.sprite.texture = last
                } else if let prior = priorTexture {
                    self.sprite.texture = prior
                }
                self.sprite.removeAllActions()
                print("Berserker: dying animation completed; sprite frozen on last frame.")
            }
        } else {
            // Fallback: tint the existing texture and keep it visible
            print("Berserker: no dying frames found; applying fallback tint.")
            let tint = SKAction.colorize(with: .red, colorBlendFactor: 0.6, duration: 0.12)
            sprite.run(tint) { [weak self] in
                self?.sprite.removeAllActions()
                print("Berserker: fallback tint applied; sprite frozen.")
            }
        }

        // Disable physics interactions but keep the node present on the field permanently
        sprite.physicsBody?.categoryBitMask = 0
        sprite.physicsBody?.contactTestBitMask = 0
        sprite.physicsBody?.collisionBitMask = 0
    }
}
