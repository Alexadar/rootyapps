import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

class GameScene: SKScene {

    // MARK: - Game Objects
    private var playerEntity: Player!
    private var gameMap: SKSpriteNode!
    private var bullets: [Bullet] = []
    private var monsters: [Monster] = []
    private var crosshair: SKSpriteNode!
#if os(macOS)
    private var trackingArea: NSTrackingArea?
#endif

    // Debug visuals to verify touch control regions (shown only on non-mac platforms)
    private var debugLeftRegion: SKSpriteNode?
    private var debugRightRegion: SKSpriteNode?
    // Use a generic SKNode for the knob so we can use SKShapeNode (avoid square sprite artifacts).
    private var debugJoystickKnob: SKNode?
    private var debugAimMarker: SKNode?

    // Input controller (abstracted for future mobile controls)
    private var inputController: InputController!

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
        #if !os(macOS)
        // Enable multitouch so movement and shooting can work simultaneously on mobile.
        view.isMultipleTouchEnabled = true
        #endif

        // Pause rendering when app goes to background to avoid Metal GPU errors
        #if !os(macOS)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        #else
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: NSApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        #endif

        // Enable mouse tracking and set custom cursor
        #if os(macOS)
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
        #endif
    }

    private func setupScene() {
        backgroundColor = .black
        scaleMode = .resizeFill
    }

    private func setupMap() {
        // Try to load the map background from resources
        let mapTexturePath = Bundle.main.path(forResource: "map_background", ofType: "png")
        if let texturePath = mapTexturePath {
            #if os(macOS)
            if let nsImage = NSImage(contentsOfFile: texturePath) {
                let texture = SKTexture(image: nsImage)
                gameMap = SKSpriteNode(texture: texture)
            } else {
                // Fallback to colored background
                gameMap = SKSpriteNode(color: .darkGray, size: size)
            }
            #else
            if let uiImage = UIImage(contentsOfFile: texturePath) {
                let texture = SKTexture(image: uiImage)
                gameMap = SKSpriteNode(texture: texture)
            } else {
                // Fallback to colored background
                gameMap = SKSpriteNode(color: .darkGray, size: size)
            }
            #endif
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
        // Name the player node so touch input can locate it without depending on Player type.
        playerEntity.sprite.name = "player"
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
        #if !os(macOS)
        // On mobile we don't use the mouse-driven crosshair; keep it hidden and use touch aim marker instead.
        crosshair.isHidden = true
        #endif
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
        #if os(macOS)
        inputController = KeyboardMouseInput()
        #else
        inputController = TouchInput(scene: self)

        // Debug visual regions to verify where touch controls are active (left/right halves).
        debugLeftRegion?.removeFromParent()
        debugRightRegion?.removeFromParent()
        debugJoystickKnob?.removeFromParent()
        debugAimMarker?.removeFromParent()

        // Debug regions: left/right halves but reduced to 25% height at the bottom.
        // Visible debug rectangles are intentionally semi-transparent so you can see the areas.
        let regionHeight = size.height * 0.25

        // Use an invisible container sprite for each control area and add a visible stroked rectangle
        // (3 px stroke, no transparency) so the debug boxes are clearly visible on device.
        let leftRegion = SKSpriteNode(color: SKColor.clear, size: CGSize(width: size.width/2, height: regionHeight))
        leftRegion.anchorPoint = CGPoint(x: 0, y: 0)
        leftRegion.position = CGPoint(x: 0, y: 0)
        leftRegion.zPosition = 250
        // Stroke shape for left region
        let leftStroke = SKShapeNode(rect: CGRect(origin: CGPoint.zero, size: leftRegion.size))
        leftStroke.strokeColor = SKColor.white
        leftStroke.lineWidth = 3
        leftStroke.fillColor = SKColor.clear
        leftStroke.position = CGPoint.zero
        leftStroke.zPosition = 251
        leftRegion.addChild(leftStroke)
        addChild(leftRegion)
        debugLeftRegion = leftRegion

        let rightRegion = SKSpriteNode(color: SKColor.clear, size: CGSize(width: size.width/2, height: regionHeight))
        rightRegion.anchorPoint = CGPoint(x: 0, y: 0)
        rightRegion.position = CGPoint(x: size.width/2, y: 0)
        rightRegion.zPosition = 250
        // Stroke shape for right region
        let rightStroke = SKShapeNode(rect: CGRect(origin: CGPoint.zero, size: rightRegion.size))
        rightStroke.strokeColor = SKColor.white
        rightStroke.lineWidth = 3
        rightStroke.fillColor = SKColor.clear
        rightStroke.position = CGPoint.zero
        rightStroke.zPosition = 251
        rightRegion.addChild(rightStroke)
        addChild(rightRegion)
        debugRightRegion = rightRegion

        // Knob as a circular shape (prevent square sprite artifacts). Always present and centered in its region when no touch.
        let knobShape = SKShapeNode(circleOfRadius: 18)
        knobShape.strokeColor = SKColor.white.withAlphaComponent(0.9)
        knobShape.lineWidth = 2
        knobShape.fillColor = SKColor.white.withAlphaComponent(0.06)
        knobShape.zPosition = 251
        // Place knob initially at left region center
        knobShape.position = CGPoint(x: leftRegion.size.width * 0.5, y: leftRegion.size.height * 0.5)
        knobShape.isHidden = false
        addChild(knobShape)
        debugJoystickKnob = knobShape

        // Aim marker as a single SKShapeNode to avoid any accidental square sprite artifacts.
        // Always present and centered in right region when no touch.
        let aimCircle = SKShapeNode(circleOfRadius: 16)
        aimCircle.strokeColor = .red
        aimCircle.lineWidth = 2
        aimCircle.fillColor = SKColor.red.withAlphaComponent(0.12)
        aimCircle.zPosition = 251
        aimCircle.isHidden = false
        aimCircle.position = CGPoint(x: rightRegion.position.x + rightRegion.size.width * 0.5, y: rightRegion.size.height * 0.5)
        addChild(aimCircle)
        debugAimMarker = aimCircle
        #endif
    }

    // MARK: - Window / focus handling
#if os(macOS)
    @objc private func windowDidResignKey(_ notification: Notification) {
        NSCursor.unhide()
        NSCursor.arrow.set()
    }
#endif

    // Background / foreground handlers to pause/resume rendering and avoid Metal submission from background.
    #if !os(macOS)
    @objc private func appDidEnterBackground() {
        // Pause the SKView to stop metal work when app is backgrounded.
        self.view?.isPaused = true
    }

    @objc private func appWillEnterForeground() {
        // Resume rendering when the app returns to foreground.
        self.view?.isPaused = false
    }
    #else
    @objc private func appWillResignActive(_ notification: Notification) {
        self.view?.isPaused = true
    }

    @objc private func appDidBecomeActive(_ notification: Notification) {
        self.view?.isPaused = false
    }
    #endif

    override func willMove(from view: SKView?) {
        if let v = view {
            super.willMove(from: v)
        } else {
            super.willMove(from: SKView())
        }
#if os(macOS)
        NSCursor.unhide()
        NSCursor.arrow.set()
        if let ta = trackingArea, let v = view {
            v.removeTrackingArea(ta)
            trackingArea = nil
        }
#endif
        NotificationCenter.default.removeObserver(self)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

     // MARK: - Input Handling (forward to input controller + debug keys)
#if os(macOS)
    override func keyDown(with event: NSEvent) {
        (inputController as? KeyboardMouseInput)?.keyDown(event)

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
        (inputController as? KeyboardMouseInput)?.keyUp(event)
    }

    override func mouseMoved(with event: NSEvent) {
        let location = event.location(in: self)
        crosshair.position = location
        (inputController as? KeyboardMouseInput)?.mouseMoved(to: location)
        playerEntity.aimToward(point: location)
    }

    override func mouseDown(with event: NSEvent) {
        (inputController as? KeyboardMouseInput)?.requestShoot()
    }

    override func mouseEntered(with event: NSEvent) {
        crosshair.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.unhide()
        NSCursor.arrow.set()
        crosshair.isHidden = false
    }
#else
    // Touch handling on iOS/tvOS: forward to TouchInput
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let tInput = inputController as? TouchInput {
            tInput.touchesBegan(touches, in: self)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let tInput = inputController as? TouchInput {
            tInput.touchesMoved(touches, in: self)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let tInput = inputController as? TouchInput {
            tInput.touchesEnded(touches, in: self)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let tInput = inputController as? TouchInput {
            tInput.touchesCancelled(touches, in: self)
        }
    }
#endif

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
#if os(macOS)
        if let win = view?.window, let v = view {
            let global = NSEvent.mouseLocation
            let windowPoint = win.convertPoint(fromScreen: global)
            let pointInView = v.convert(windowPoint, from: nil)
            if !v.bounds.contains(pointInView) {
                NSCursor.unhide()
                NSCursor.arrow.set()
            }
        }
#endif

        // Handle player movement via input controller
        let moveVec = inputController.movementVector()
        playerEntity.move(by: moveVec, deltaTime: deltaTime, sceneSize: size)

        // Update debug visuals for touch controls on mobile (left/right regions + joystick knob + aim marker)
        #if !os(macOS)
        if inputController is TouchInput {
            // Joystick knob: center in left region and offset by movement vector scaled by joystick radius
            if let knob = debugJoystickKnob, let leftRegion = debugLeftRegion {
                // Center of left control region
                let center = CGPoint(x: leftRegion.position.x + leftRegion.size.width * 0.5, y: leftRegion.position.y + leftRegion.size.height * 0.5)
                let radius: CGFloat = 60.0
                // Always show knob; when movement vector is zero it stays at the region center.
                knob.isHidden = false
                knob.position = CGPoint(x: center.x + moveVec.dx * radius, y: center.y + moveVec.dy * radius)
            }

            // Aim marker: if player is actively aiming use computed aim point (scene coords),
            // otherwise show the right control area's center so the circle remains visible.
            if let aimMarker = debugAimMarker, let rightRegion = debugRightRegion {
                if let aim = inputController.aimPoint() {
                    aimMarker.position = aim
                } else {
                    // Right region center in scene coords
                    let rightCenter = CGPoint(x: rightRegion.position.x + rightRegion.size.width * 0.5, y: rightRegion.position.y + rightRegion.size.height * 0.5)
                    aimMarker.position = rightCenter
                }
                aimMarker.isHidden = false
            }
        } else {
            // Hide debug visuals if not using touch input
            debugJoystickKnob?.isHidden = true
            debugAimMarker?.isHidden = true
        }
        #endif

        // Aim and shooting
        #if os(macOS)
        if let aim = inputController.aimPoint() {
            crosshair.position = aim
            playerEntity.aimToward(point: aim)
        }
        #else
        // On mobile: inputController.aimPoint() returns an absolute point computed around the player.
        if let aim = inputController.aimPoint() {
            playerEntity.aimToward(point: aim)
        }
        #endif

        if inputController.isShooting() {
            // Prefer aim point if available; on mobile aimPoint() is already oriented around the player.
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
