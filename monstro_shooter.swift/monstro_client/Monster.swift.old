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

    // Utility: load textures from a folder inside bundle (e.g. "monsters/berserker/walk").
    // Robust: tries inDirectory first, then falls back to scanning all PNGs and matching by filename prefix
    // (useful because Xcode may copy resources flattened into the bundle root).
    func loadTextures(fromDirectory subpath: String) -> [SKTexture] {
        var textures: [SKTexture] = []

        // 1) Try to load resources from the exact directory inside the bundle.
        var rawPaths = Bundle.main.paths(forResourcesOfType: "png", inDirectory: subpath)

        // 2) Fallback: if nothing found, try to match by filename prefix.
        if rawPaths.isEmpty {
            // Derive a filename prefix from the last path component, e.g. "monsters/berserker/walk" -> "walk_"
            let comp = subpath.components(separatedBy: "/").last ?? subpath
            let prefix = comp + "_"

            // Scan all PNGs in the bundle root and filter by prefix
            let allPngs = Bundle.main.paths(forResourcesOfType: "png", inDirectory: nil)
            rawPaths = allPngs.filter { path in
                let name = (path as NSString).lastPathComponent
                return name.hasPrefix(prefix)
            }
        }

        // Sort by filename to ensure frame order
        let sortedPaths = rawPaths.sorted { (a, b) -> Bool in
            return (a as NSString).lastPathComponent < (b as NSString).lastPathComponent
        }

        for p in sortedPaths {
#if os(macOS)
            if let img = NSImage(contentsOfFile: p) {
                let tex = SKTexture(image: img)
                textures.append(tex)
            }
#else
            if let uiImg = UIImage(contentsOfFile: p) {
                let tex = SKTexture(image: uiImg)
                textures.append(tex)
            }
#endif
        }

        return textures
    }
}

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
    }

    override func setup(at position: CGPoint, targetPosition: CGPoint) {
        // Load frames (if available)
        walkFrames = loadTextures(fromDirectory: "monsters/berserker/walk")
        dyingFrames = loadTextures(fromDirectory: "monsters/berserker/dying")

        // Debug logging to verify resource discovery at runtime
        let exactWalkPaths = Bundle.main.paths(forResourcesOfType: "png", inDirectory: "monsters/berserker/walk")
        let exactDyingPaths = Bundle.main.paths(forResourcesOfType: "png", inDirectory: "monsters/berserker/dying")
        let rootPngs = Bundle.main.paths(forResourcesOfType: "png", inDirectory: nil)
        print("Berserker resource debug: exactWalk=\\(exactWalkPaths.count), exactDying=\\(exactDyingPaths.count), rootPngs=\\(rootPngs.count)")
        if !exactWalkPaths.isEmpty { print("exactWalk sample: \\((exactWalkPaths as NSArray).subarray(with: NSRange(location: 0, length: min(5, exactWalkPaths.count))) )") }
        if !exactDyingPaths.isEmpty { print("exactDying sample: \\((exactDyingPaths as NSArray).subarray(with: NSRange(location: 0, length: min(5, exactDyingPaths.count))) )") }

        print("Loaded frames counts -> walkFrames:\\(walkFrames.count) dyingFrames:\\(dyingFrames.count)")

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
    }

    override func update(deltaTime: TimeInterval, playerPosition: CGPoint) {
        guard !isDying else { return }

        // Movement same as base but ensure sprite orientation and size
        let dx = playerPosition.x - sprite.position.x
        let dy = playerPosition.y - sprite.position.y
        let distance = sqrt(dx*dx + dy*dy)

        if distance > 0 {
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

        // Log entry for diagnostics
        print("Berserker.die() called. dyingFrames.count = \\(dyingFrames.count)")

        // Stop walking animation but keep current texture/orientation
        sprite.removeAction(forKey: "walk")

        // Ensure current texture is preserved before playing dying animation
        let priorTexture = sprite.texture

        // Play dying animation if available, then set last frame as static texture and stop actions.
        if !dyingFrames.isEmpty {
            print("Berserker: running dying animation with \\(dyingFrames.count) frames")
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
