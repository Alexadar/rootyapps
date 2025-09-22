import SpriteKit
import AppKit

class GameScene: SKScene {

    // MARK: - Game Objects
    private var player: SKSpriteNode!
    private var gameMap: SKSpriteNode!
    private var bullets: [SKSpriteNode] = []
    private var monsters: [Monster] = []
    private var crosshair: SKSpriteNode!
    private var trackingArea: NSTrackingArea?

    // MARK: - Game Settings
    private let playerSpeed: CGFloat = 300.0
    private let bulletSpeed: CGFloat = 800.0
    private let monsterSpawnInterval: TimeInterval = 2.0

    // MARK: - Input State
    private var keysPressed = Set<UInt16>()
    private var lastMonsterSpawn: TimeInterval = 0

    // Debug rotation controls (R = toggle auto-apply, Q/E = adjust offset)
    private var debugRotationEnabled: Bool = false
    private var debugRotationOffset: CGFloat = 0.0
    private let debugRotationStep: CGFloat = .pi / 8
    private var debugRotationLabel: SKLabelNode!

    // MARK: - Scene Setup
    override func didMove(to view: SKView) {
        setupScene()
        setupPlayer()
        setupMap()
        setupCrosshair()
        setupPhysics()
        setupDebugLabel()

        // Enable mouse tracking and set custom cursor
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self, let window = strongSelf.view?.window, let view = strongSelf.view else { return }
            window.acceptsMouseMovedEvents = true
            window.makeFirstResponder(strongSelf)

            // Set up tracking area for mouse enter/exit events
            let trackingArea = NSTrackingArea(
                rect: view.bounds,
                options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
                owner: strongSelf,
                userInfo: nil
            )
            view.addTrackingArea(trackingArea)
            strongSelf.trackingArea = trackingArea
            print("GameScene: tracking area added; view.bounds = \\(view.bounds)")
        }
    }

    private func setupScene() {
        backgroundColor = .black
        scaleMode = .resizeFill
    }

    private func setupMap() {
        // Try to load the map background from resources
        let mapTexturePath = Bundle.main.path(forResource: "map_background", ofType: "png")
        if let texturePath = mapTexturePath,
           let nsImage = NSImage(contentsOfFile: texturePath) {
            let texture = SKTexture(image: nsImage)
            gameMap = SKSpriteNode(texture: texture)
        } else {
            // Fallback to colored background
            gameMap = SKSpriteNode(color: .darkGray, size: size)
        }

        gameMap.position = CGPoint(x: size.width/2, y: size.height/2)
        gameMap.size = size
        gameMap.zPosition = -10
        addChild(gameMap)
    }

    private func setupPlayer() {
        // Try to load exoskeleton texture atlas and extract just the green body
        if let atlas = TextureAtlas(atlasImagePath: "exoskeletons_0.png", xmlPath: "exoskeletons_0.xml"),
           let bodyTexture = atlas.getTexture(named: "_0_exoskeleton0000") {
            player = SKSpriteNode(texture: bodyTexture)
            player.size = CGSize(width: 60, height: 60)
            print("Loaded player from Assets.xcassets Player")
        } else {
            // Fallback player
            player = SKSpriteNode(color: .green, size: CGSize(width: 40, height: 40))
            print("Using fallback player sprite")
        }

        player.position = CGPoint(x: size.width/2, y: size.height/2)
        player.zPosition = 10
        player.name = "player"

        // Setup player physics
        player.physicsBody = SKPhysicsBody(rectangleOf: player.size)
        player.physicsBody?.categoryBitMask = PhysicsCategory.player
        player.physicsBody?.contactTestBitMask = PhysicsCategory.monster
        player.physicsBody?.collisionBitMask = 0
        player.physicsBody?.affectedByGravity = false

        addChild(player)
    }

    private func setupCrosshair() {
        // Create a simple crosshair using lines
        crosshair = SKSpriteNode()
        crosshair.zPosition = 100 // Always on top

        // Horizontal line
        let horizontalLine = SKSpriteNode(color: .white, size: CGSize(width: 20, height: 2))
        horizontalLine.position = CGPoint.zero
        crosshair.addChild(horizontalLine)

        // Vertical line
        let verticalLine = SKSpriteNode(color: .white, size: CGSize(width: 2, height: 20))
        verticalLine.position = CGPoint.zero
        crosshair.addChild(verticalLine)

        // Center dot
        let centerDot = SKSpriteNode(color: .red, size: CGSize(width: 3, height: 3))
        centerDot.position = CGPoint.zero
        crosshair.addChild(centerDot)

        // Add outline for better visibility
        let outlineH = SKSpriteNode(color: .black, size: CGSize(width: 22, height: 4))
        outlineH.position = CGPoint.zero
        outlineH.zPosition = -1
        crosshair.addChild(outlineH)

        let outlineV = SKSpriteNode(color: .black, size: CGSize(width: 4, height: 22))
        outlineV.position = CGPoint.zero
        outlineV.zPosition = -1
        crosshair.addChild(outlineV)

        crosshair.position = CGPoint(x: size.width/2, y: size.height/2)
        addChild(crosshair)
    }

    private func setupPhysics() {
        physicsWorld.gravity = CGVector.zero
        physicsWorld.contactDelegate = self
    }

    // On-screen debug label to show current rotation toggle/offset and key hints
    private func setupDebugLabel() {
        debugRotationLabel = SKLabelNode(fontNamed: "Menlo")
        debugRotationLabel.fontSize = 12
        debugRotationLabel.fontColor = .white
        debugRotationLabel.horizontalAlignmentMode = .left
        debugRotationLabel.verticalAlignmentMode = .top
        debugRotationLabel.position = CGPoint(x: 10, y: size.height - 10)
        debugRotationLabel.zPosition = 200
        addChild(debugRotationLabel)
        updateDebugLabel()
    }

    private func updateDebugLabel() {
        debugRotationLabel.text = "R: \(debugRotationEnabled ? "ON" : "OFF")  Offset: \(String(format: "%.2f", debugRotationOffset))  (Q/E adjust, R toggle)"
    }

    // Handle window focus loss and cleanup
    @objc private func windowDidResignKey(_ notification: Notification) {
        // Ensure default cursor is active when the window loses focus.
        // Use unhide() first to balance any prior hide() calls, then set the arrow.
        NSCursor.unhide()
        NSCursor.arrow.set()
    }

    override func willMove(from view: SKView?) {
        // Some SKScene APIs expect a non-optional SKView at the super call.
        // Safely unwrap when available; otherwise call with a temporary SKView to satisfy the API.
        if let v = view {
            super.willMove(from: v)
        } else {
            super.willMove(from: SKView())
        }
        // Restore system cursor and remove our tracking area when the scene is removed.
        // Call unhide() to ensure we balance any prior hide() state, then set arrow.
        NSCursor.unhide()
        NSCursor.arrow.set()
        if let ta = trackingArea, let v = view {
            v.removeTrackingArea(ta)
            trackingArea = nil
        }
        NotificationCenter.default.removeObserver(self)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Input Handling
    override func keyDown(with event: NSEvent) {
        // Standard movement keys still recorded
        keysPressed.insert(event.keyCode)

        // Debug keys:
        // R (keyCode 15) - toggle applying global rotation offset to all monsters
        // Q (keyCode 12) - decrease rotation offset
        // E (keyCode 14) - increase rotation offset
        switch event.keyCode {
        case 15: // R
            debugRotationEnabled.toggle()
            print("DebugRotation: enabled=\(debugRotationEnabled), currentOffset=\(debugRotationOffset)")
            if debugRotationEnabled {
                // immediately apply to existing monsters
                for m in monsters { m.rotationOffset = debugRotationOffset }
            }
        case 12: // Q
            debugRotationOffset -= debugRotationStep
            print("DebugRotation: offset adjusted -> \(debugRotationOffset)")
            if debugRotationEnabled {
                for m in monsters { m.rotationOffset = debugRotationOffset }
            }
        case 14: // E
            debugRotationOffset += debugRotationStep
            print("DebugRotation: offset adjusted -> \(debugRotationOffset)")
            if debugRotationEnabled {
                for m in monsters { m.rotationOffset = debugRotationOffset }
            }
        default:
            break
        }
    }

    override func keyUp(with event: NSEvent) {
        keysPressed.remove(event.keyCode)
    }

    override func mouseMoved(with event: NSEvent) {
        let location = event.location(in: self)
        // Update crosshair position
        crosshair.position = location
        // Aim player toward crosshair
        aimPlayerToward(point: location)
    }

    override func mouseDown(with event: NSEvent) {
        // Shoot toward crosshair position
        shoot(toward: crosshair.position)
    }

    override func mouseEntered(with event: NSEvent) {
        print("GameScene: mouseEntered")
        // Keep behavior simple: do not hide or modify system cursor.
        crosshair.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        print("GameScene: mouseExited")
        // Ensure system cursor is visible when leaving the view.
        // Call unhide() first to recover from any unmatched hide() calls, then set arrow.
        NSCursor.unhide()
        NSCursor.arrow.set()
        // Keep crosshair visible so the player retains aim
        crosshair.isHidden = false
    }

    private func aimPlayerToward(point: CGPoint) {
        let dx = point.x - player.position.x
        let dy = point.y - player.position.y
        let angle = atan2(dy, dx)
        player.zRotation = angle - (.pi / 2) // Adjust for sprite orientation
    }

    private func shoot(toward point: CGPoint) {
        let bullet = createBullet()
        bullet.position = player.position

        let dx = point.x - player.position.x
        let dy = point.y - player.position.y
        let distance = sqrt(dx*dx + dy*dy)

        guard distance > 0 else { return }

        let normalizedDx = dx / distance
        let normalizedDy = dy / distance

        bullet.physicsBody = SKPhysicsBody(circleOfRadius: bullet.size.width/2)
        bullet.physicsBody?.categoryBitMask = PhysicsCategory.bullet
        bullet.physicsBody?.contactTestBitMask = PhysicsCategory.monster
        bullet.physicsBody?.collisionBitMask = 0
        bullet.physicsBody?.affectedByGravity = false
        bullet.physicsBody?.velocity = CGVector(
            dx: normalizedDx * bulletSpeed,
            dy: normalizedDy * bulletSpeed
        )

        addChild(bullet)
        bullets.append(bullet)

        // Remove bullet after 3 seconds
        let removeAction = SKAction.sequence([
            SKAction.wait(forDuration: 3.0),
            SKAction.removeFromParent()
        ])
        bullet.run(removeAction) { [weak self] in
            self?.bullets.removeAll { $0 == bullet }
        }
    }

    private func createBullet() -> SKSpriteNode {
        // Try to load bullet texture from weapons spritesheet
        let weaponsPath = Bundle.main.path(forResource: "weapons", ofType: "png")
        if let texturePath = weaponsPath,
           let nsImage = NSImage(contentsOfFile: texturePath) {
            let texture = SKTexture(image: nsImage)
            let bullet = SKSpriteNode(texture: texture)
            bullet.size = CGSize(width: 8, height: 8)
            bullet.name = "bullet"
            bullet.zPosition = 5
            return bullet
        } else {
            // Fallback bullet
            let bullet = SKSpriteNode(color: .yellow, size: CGSize(width: 6, height: 6))
            bullet.name = "bullet"
            bullet.zPosition = 5
            return bullet
        }
    }

    // MARK: - Monster Management
    private func spawnMonster() {
        let monster = Berserker()

        // Spawn at random edge of screen
        let spawnSide = Int.random(in: 0...3)
        var spawnPosition: CGPoint

        switch spawnSide {
        case 0: // Top
            spawnPosition = CGPoint(x: CGFloat.random(in: 0...size.width), y: size.height + 50)
        case 1: // Right
            spawnPosition = CGPoint(x: size.width + 50, y: CGFloat.random(in: 0...size.height))
        case 2: // Bottom
            spawnPosition = CGPoint(x: CGFloat.random(in: 0...size.width), y: -50)
        default: // Left
            spawnPosition = CGPoint(x: -50, y: CGFloat.random(in: 0...size.height))
        }

        monster.setup(at: spawnPosition, targetPosition: player.position)
        addChild(monster.sprite)
        monsters.append(monster)
    }

    private func updateMonsters(_ deltaTime: TimeInterval) {
        for monster in monsters {
            // If debug override is enabled, force all monsters to use the global offset
            if debugRotationEnabled {
                monster.rotationOffset = debugRotationOffset
            }
            monster.update(deltaTime: deltaTime, playerPosition: player.position)
        }

        // Remove monsters that are too far away
        monsters.removeAll { monster in
            let distance = sqrt(pow(monster.sprite.position.x - player.position.x, 2) +
                               pow(monster.sprite.position.y - player.position.y, 2))
            if distance > 2000 {
                monster.sprite.removeFromParent()
                return true
            }
            return false
        }
    }

    // MARK: - Game Loop
    private var lastUpdateTime: TimeInterval = 0

    override func update(_ currentTime: TimeInterval) {
        let deltaTime: TimeInterval
        if lastUpdateTime > 0 {
            deltaTime = currentTime - lastUpdateTime
        } else {
            deltaTime = 0
        }
        lastUpdateTime = currentTime

        // Diagnostic fallback: if the mouse is actually outside the SKView bounds but the system cursor
        // has been hidden accidentally, restore it. This runs every frame as a safety net.
        if let win = view?.window, let v = view {
            let global = NSEvent.mouseLocation
            let windowPoint = win.convertPoint(fromScreen: global)
            let pointInView = v.convert(windowPoint, from: nil)
            if !v.bounds.contains(pointInView) {
                NSCursor.unhide()
                NSCursor.arrow.set()
            }
        }

        handlePlayerMovement(deltaTime)
        updateMonsters(deltaTime)
        updateDebugLabel()

        // Spawn monsters periodically
        if currentTime - lastMonsterSpawn > monsterSpawnInterval {
            spawnMonster()
            lastMonsterSpawn = currentTime
        }

        // Clean up off-screen bullets
        cleanupBullets()
    }

    private func handlePlayerMovement(_ deltaTime: TimeInterval) {
        var moveVector = CGVector.zero

        // WASD movement (W:13, A:0, S:1, D:2)
        if keysPressed.contains(13) { moveVector.dy += 1 } // W
        if keysPressed.contains(1) { moveVector.dy -= 1 }  // S
        if keysPressed.contains(0) { moveVector.dx -= 1 }  // A
        if keysPressed.contains(2) { moveVector.dx += 1 }  // D

        // Normalize diagonal movement
        let length = sqrt(moveVector.dx * moveVector.dx + moveVector.dy * moveVector.dy)
        if length > 0 {
            moveVector.dx /= length
            moveVector.dy /= length

            let newX = player.position.x + moveVector.dx * playerSpeed * CGFloat(deltaTime)
            let newY = player.position.y + moveVector.dy * playerSpeed * CGFloat(deltaTime)

            // Keep player within bounds
            let halfWidth = player.size.width / 2
            let halfHeight = player.size.height / 2

            player.position.x = max(halfWidth, min(size.width - halfWidth, newX))
            player.position.y = max(halfHeight, min(size.height - halfHeight, newY))
        }
    }

    private func cleanupBullets() {
        bullets.removeAll { bullet in
            if !frame.contains(bullet.position) {
                bullet.removeFromParent()
                return true
            }
            return false
        }
    }
}

// MARK: - Physics Contact Delegate
extension GameScene: SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {
        let bodyA = contact.bodyA
        let bodyB = contact.bodyB

        // Bullet hits monster
        if (bodyA.categoryBitMask == PhysicsCategory.bullet && bodyB.categoryBitMask == PhysicsCategory.monster) ||
           (bodyA.categoryBitMask == PhysicsCategory.monster && bodyB.categoryBitMask == PhysicsCategory.bullet) {

            let bulletNode = bodyA.categoryBitMask == PhysicsCategory.bullet ? bodyA.node : bodyB.node
            let monsterNode = bodyA.categoryBitMask == PhysicsCategory.monster ? bodyA.node : bodyB.node

            // Remove bullet
            if let bullet = bulletNode as? SKSpriteNode {
                bullet.removeFromParent()
                bullets.removeAll { $0 == bullet }
            }

            // Find monster and trigger its death animation (do not remove immediately)
            if let monsterSprite = monsterNode as? SKSpriteNode {
                if let monsterIndex = monsters.firstIndex(where: { $0.sprite == monsterSprite }) {
                    // Trigger dying sequence on the Monster instance instead of removing it.
                    monsters[monsterIndex].die()

                    // Disable further physics interactions for the dead monster
                    monsters[monsterIndex].sprite.physicsBody?.categoryBitMask = 0
                    monsters[monsterIndex].sprite.physicsBody?.contactTestBitMask = 0
                    monsters[monsterIndex].sprite.physicsBody?.collisionBitMask = 0
                }
            }
        }

        // Player hits monster (game over condition)
        if (bodyA.categoryBitMask == PhysicsCategory.player && bodyB.categoryBitMask == PhysicsCategory.monster) ||
           (bodyA.categoryBitMask == PhysicsCategory.monster && bodyB.categoryBitMask == PhysicsCategory.player) {
            // Handle player death here
            print("Player hit by monster!")
        }
    }
}

// MARK: - Physics Categories
struct PhysicsCategory {
    static let player: UInt32 = 1
    static let monster: UInt32 = 2
    static let bullet: UInt32 = 4
}

 // MARK: - Monster Class (generic) + Berserker subclass using folder-based animations
class Monster {
    var sprite: SKSpriteNode!
    var speed: CGFloat = 100.0
    var boxSize: CGSize = CGSize(width: 28, height: 28)
    var rotationOffset: CGFloat = .pi / 4
    private var animationTimer: TimeInterval = 0

    init() {}

    /// Default setup: simple colored placeholder (kept for safety)
    func setup(at position: CGPoint, targetPosition: CGPoint) {
        sprite = SKSpriteNode(color: NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0), size: boxSize)
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
            if let img = NSImage(contentsOfFile: p) {
                let tex = SKTexture(image: img)
                textures.append(tex)
            }
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
        print("Berserker resource debug: exactWalk=\(exactWalkPaths.count), exactDying=\(exactDyingPaths.count), rootPngs=\(rootPngs.count)")
        if !exactWalkPaths.isEmpty { print("exactWalk sample: \((exactWalkPaths as NSArray).subarray(with: NSRange(location: 0, length: min(5, exactWalkPaths.count))) )") }
        if !exactDyingPaths.isEmpty { print("exactDying sample: \((exactDyingPaths as NSArray).subarray(with: NSRange(location: 0, length: min(5, exactDyingPaths.count))) )") }

        print("Loaded frames counts -> walkFrames:\(walkFrames.count) dyingFrames:\(dyingFrames.count)")

        // Use first walk frame as initial texture if available
        if let first = walkFrames.first {
            sprite = SKSpriteNode(texture: first, size: boxSize)
        } else {
            // fallback visual
            sprite = SKSpriteNode(color: NSColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 1.0), size: boxSize)
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
        print("Berserker.die() called. dyingFrames.count = \(dyingFrames.count)")

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
