import SpriteKit
import AppKit

class GameScene: SKScene {

    // MARK: - Game Objects
    private var playerEntity: Player!
    private var gameMap: SKSpriteNode!
    private var bullets: [Bullet] = []
    private var monsters: [Monster] = []
    private var crosshair: SKSpriteNode!
    private var trackingArea: NSTrackingArea?

    // Input controller (abstracted for future mobile controls)
    private var inputController: KeyboardMouseInput!

    // MARK: - Game Settings
    private let bulletSpeed: CGFloat = 800.0
    private let monsterSpawnInterval: TimeInterval = 2.0

    // MARK: - Input / Timing State
    private var lastMonsterSpawn: TimeInterval = 0

    // Debug rotation controls (R = toggle auto-apply, Q/E = adjust offset)
    private var debugRotationEnabled: Bool = false
    private var debugRotationOffset: CGFloat = 0.0
    private let debugRotationStep: CGFloat = .pi / 8
    private var debugRotationLabel: SKLabelNode!

    // MARK: - Scene Setup
    override func didMove(to view: SKView) {
        setupScene()
        setupMap()
        setupPlayer()
        setupCrosshair()
        setupPhysics()
        setupDebugLabel()
        setupInput()

        // Enable mouse tracking and set custom cursor
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self, let window = strongSelf.view?.window, let view = strongSelf.view else { return }
            window.acceptsMouseMovedEvents = true
            window.makeFirstResponder(strongSelf)

            let trackingArea = NSTrackingArea(
                rect: view.bounds,
                options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
                owner: strongSelf,
                userInfo: nil
            )
            view.addTrackingArea(trackingArea)
            strongSelf.trackingArea = trackingArea
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
        let initialPos = CGPoint(x: size.width/2, y: size.height/2)
        if let p = Player(initialPosition: initialPos) {
            playerEntity = p
        } else {
            // Player initializer is failable but fallback should still produce a sprite.
            playerEntity = Player(initialPosition: initialPos)
        }
        addChild(playerEntity.sprite)
    }

    private func setupCrosshair() {
        crosshair = SKSpriteNode()
        crosshair.zPosition = 100 // Always on top

        let horizontalLine = SKSpriteNode(color: .white, size: CGSize(width: 20, height: 2))
        horizontalLine.position = CGPoint.zero
        crosshair.addChild(horizontalLine)

        let verticalLine = SKSpriteNode(color: .white, size: CGSize(width: 2, height: 20))
        verticalLine.position = CGPoint.zero
        crosshair.addChild(verticalLine)

        let centerDot = SKSpriteNode(color: .red, size: CGSize(width: 3, height: 3))
        centerDot.position = CGPoint.zero
        crosshair.addChild(centerDot)

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

    private func setupInput() {
        inputController = KeyboardMouseInput()
    }

    // MARK: - Window / focus handling
    @objc private func windowDidResignKey(_ notification: Notification) {
        NSCursor.unhide()
        NSCursor.arrow.set()
    }

    override func willMove(from view: SKView?) {
        if let v = view {
            super.willMove(from: v)
        } else {
            super.willMove(from: SKView())
        }
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

    // MARK: - Input Handling (forward to input controller + debug keys)
    override func keyDown(with event: NSEvent) {
        inputController.keyDown(event)

        // Debug keys:
        switch event.keyCode {
        case 15: // R
            debugRotationEnabled.toggle()
            if debugRotationEnabled {
                for m in monsters { m.rotationOffset = debugRotationOffset }
            }
        case 12: // Q
            debugRotationOffset -= debugRotationStep
            if debugRotationEnabled {
                for m in monsters { m.rotationOffset = debugRotationOffset }
            }
        case 14: // E
            debugRotationOffset += debugRotationStep
            if debugRotationEnabled {
                for m in monsters { m.rotationOffset = debugRotationOffset }
            }
        default:
            break
        }
    }

    override func keyUp(with event: NSEvent) {
        inputController.keyUp(event)
    }

    override func mouseMoved(with event: NSEvent) {
        let location = event.location(in: self)
        crosshair.position = location
        inputController.mouseMoved(to: location)
        playerEntity.aimToward(point: location)
    }

    override func mouseDown(with event: NSEvent) {
        inputController.requestShoot()
    }

    override func mouseEntered(with event: NSEvent) {
        crosshair.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.unhide()
        NSCursor.arrow.set()
        crosshair.isHidden = false
    }

    // MARK: - Shooting
    private func shoot(toward point: CGPoint) {
        // Compute normalized direction and velocity
        let dx = point.x - playerEntity.sprite.position.x
        let dy = point.y - playerEntity.sprite.position.y
        let distance = sqrt(dx*dx + dy*dy)
        guard distance > 0 else { return }
        let ndx = dx / distance
        let ndy = dy / distance
        let velocity = CGVector(dx: ndx * bulletSpeed, dy: ndy * bulletSpeed)

        let bullet = Bullet.create(at: playerEntity.sprite.position, velocity: velocity)
        addChild(bullet.sprite)
        bullets.append(bullet)
    }

    // MARK: - Monster Management
    private func spawnMonster() {
        let monster = Berserker()
        // Spawn at random edge of screen
        let spawnSide = Int.random(in: 0...3)
        var spawnPosition: CGPoint

        switch spawnSide {
        case 0:
            spawnPosition = CGPoint(x: CGFloat.random(in: 0...size.width), y: size.height + 50)
        case 1:
            spawnPosition = CGPoint(x: size.width + 50, y: CGFloat.random(in: 0...size.height))
        case 2:
            spawnPosition = CGPoint(x: CGFloat.random(in: 0...size.width), y: -50)
        default:
            spawnPosition = CGPoint(x: -50, y: CGFloat.random(in: 0...size.height))
        }

        monster.setup(at: spawnPosition, targetPosition: playerEntity.sprite.position)
        addChild(monster.sprite)
        monsters.append(monster)
    }

    private func updateMonsters(_ deltaTime: TimeInterval) {
        for monster in monsters {
            if debugRotationEnabled {
                monster.rotationOffset = debugRotationOffset
            }
            monster.update(deltaTime: deltaTime, playerPosition: playerEntity.sprite.position)
        }

        monsters.removeAll { monster in
            let distance = sqrt(pow(monster.sprite.position.x - playerEntity.sprite.position.x, 2) +
                               pow(monster.sprite.position.y - playerEntity.sprite.position.y, 2))
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

        // Safety: restore cursor if outside view bounds
        if let win = view?.window, let v = view {
            let global = NSEvent.mouseLocation
            let windowPoint = win.convertPoint(fromScreen: global)
            let pointInView = v.convert(windowPoint, from: nil)
            if !v.bounds.contains(pointInView) {
                NSCursor.unhide()
                NSCursor.arrow.set()
            }
        }

        // Handle player movement via input controller
        let moveVec = inputController.movementVector()
        playerEntity.move(by: moveVec, deltaTime: deltaTime, sceneSize: size)

        // Aim and shooting
        if let aim = inputController.aimPoint() {
            crosshair.position = aim
            playerEntity.aimToward(point: aim)
        }

        if inputController.isShooting() {
            // Prefer aim point if available, otherwise use crosshair
            let aimPoint = inputController.aimPoint() ?? crosshair.position
            shoot(toward: aimPoint)
        }

        updateMonsters(deltaTime)
        updateDebugLabel()

        if currentTime - lastMonsterSpawn > monsterSpawnInterval {
            spawnMonster()
            lastMonsterSpawn = currentTime
        }

        cleanupBullets()
    }

    private func cleanupBullets() {
        bullets.removeAll { bullet in
            if !frame.contains(bullet.sprite.position) {
                bullet.sprite.removeFromParent()
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
            if let bNode = bulletNode as? SKSpriteNode {
                // Find Bullet wrapper and remove
                if let idx = bullets.firstIndex(where: { $0.sprite == bNode }) {
                    let b = bullets[idx]
                    b.sprite.removeFromParent()
                    bullets.remove(at: idx)
                } else {
                    bNode.removeFromParent()
                }
            }

            // Find monster and trigger its death animation (do not remove immediately)
            if let monsterSprite = monsterNode as? SKSpriteNode {
                if let monsterIndex = monsters.firstIndex(where: { $0.sprite == monsterSprite }) {
                    monsters[monsterIndex].die()
                    monsters[monsterIndex].sprite.physicsBody?.categoryBitMask = 0
                    monsters[monsterIndex].sprite.physicsBody?.contactTestBitMask = 0
                    monsters[monsterIndex].sprite.physicsBody?.collisionBitMask = 0
                }
            }
        }

        // Player hits monster (game over condition)
        if (bodyA.categoryBitMask == PhysicsCategory.player && bodyB.categoryBitMask == PhysicsCategory.monster) ||
           (bodyA.categoryBitMask == PhysicsCategory.monster && bodyB.categoryBitMask == PhysicsCategory.player) {
            print("Player hit by monster!")
        }
    }
}
