import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

class GameScene: SKScene {

    // MARK: - Game Objects
    // Make player optional and guard uses so the scene won't crash if something initialized out-of-order.
    private var playerEntity: Player?
    private var gameMap: SKSpriteNode?
    private var bullets: [Bullet] = []
    private var monsters: [Monster] = []
    private var crosshair: SKSpriteNode?
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
    private var inputController: InputController?
    // Optional external input (e.g. AI) that overrides automatic selection for menu scripting.
    var externalInput: InputController?
    // When true the touch debug regions are shown even if the active input is not TouchInput.
    // Useful for the animated main-menu where we want touch regions visible as an overlay.
    var showTouchDebug: Bool = false

    // MARK: - Game Settings
    private let bulletSpeed: CGFloat = 800.0
    private var monsterSpawnInterval: TimeInterval = 2.0

    // MARK: - Input / Timing State
    private var lastMonsterSpawn: TimeInterval = 0

    // Debug rotation controls (R = toggle auto-apply, Q/E = adjust offset)
    private var debugRotationEnabled: Bool = false
    private var debugRotationOffset: CGFloat = 0.0
    private let debugRotationStep: CGFloat = .pi / 8
    private var debugRotationLabel: SKLabelNode?

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

        // If externalInput is present we treat this scene as the animated main menu:
        // - speed up monster spawn rate
        // - pre-spawn a few monsters so the AI has immediate targets
        // - reset AI internal timers
        if externalInput != nil {
            monsterSpawnInterval = 1.0
            for _ in 0..<3 { spawnMonster() }
            if let ai = externalInput as? AIInput {
                ai.reset()
                // if player already created, ensure AI knows the player node (setupPlayer runs before didMove child additions)
                if let p = playerEntity {
                    ai.setPlayerNode(p.sprite)
                }
            }
        }

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
    
    /// Prepare the scene to run as an animated main menu (start AI scripting, spawn targets).
    /// Call this after the SpriteView / scene is presented.
    func startMenuScripting() {
        // Speed up spawns and give AI immediate targets.
        monsterSpawnInterval = 1.0
        lastMonsterSpawn = 0
        for _ in 0..<3 { spawnMonster() }
        if let ai = externalInput as? AIInput {
            ai.reset()
            if let p = playerEntity {
                ai.setPlayerNode(p.sprite)
            }
        }
    }
    
    private func setupScene() {
        // Use center anchor to avoid visible shifting when the SpriteView resizes.
        // This restores the scene coordinate origin to the visual center of the view.
        self.anchorPoint = CGPoint(x: 0.5, y: 0.5)
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

        if let gm = gameMap {
            gm.position = CGPoint.zero
            gm.size = size
            gm.zPosition = -10
            addChild(gm)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Ensure background and debug UI match the new scene size (SpriteView may resize the scene).
        // Guard against early calls where setupMap / other setup methods haven't run yet.
        if let gm = gameMap {
            gm.size = size
            gm.position = CGPoint.zero
        }

        // Update debug regions and visuals if they exist
        let regionHeight = size.height * 0.25
        if let left = debugLeftRegion {
            left.size = CGSize(width: size.width/2, height: regionHeight)
            // left region anchored at bottom-left of scene coordinates (scene center anchor means origin is at center)
            left.position = CGPoint(x: -size.width/2, y: -size.height/2)
            if let leftStroke = left.children.first as? SKShapeNode {
                leftStroke.path = CGPath(rect: CGRect(origin: .zero, size: left.size), transform: nil)
            }
        }

        if let right = debugRightRegion {
            right.size = CGSize(width: size.width/2, height: regionHeight)
            right.position = CGPoint(x: 0, y: -size.height/2)
            if let rightStroke = right.children.first as? SKShapeNode {
                rightStroke.path = CGPath(rect: CGRect(origin: .zero, size: right.size), transform: nil)
            }
        }

        if let knob = debugJoystickKnob, let left = debugLeftRegion {
            knob.position = CGPoint(x: left.position.x + left.size.width * 0.5, y: left.position.y + left.size.height * 0.5)
        }

        if let aim = debugAimMarker, let right = debugRightRegion {
            aim.position = CGPoint(x: right.position.x + right.size.width * 0.5, y: right.position.y + right.size.height * 0.5)
        }

        // Keep crosshair centered if needed
        if let ch = crosshair {
            ch.position = CGPoint.zero
        }
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
        if let p = playerEntity {
            p.sprite.name = "player"
            addChild(p.sprite)
            // If an external input (like AI) is provided, give it the player node so it can aim/move.
            if let ai = externalInput as? AIInput {
                ai.setPlayerNode(p.sprite)
            }
        }
    }

    private func setupCrosshair() {
        // Create crosshair locally then store into optional property once configured.
        let ch = SKSpriteNode()
        ch.zPosition = 100 // Always on top

        let horizontalLine = SKSpriteNode(color: .white, size: CGSize(width: 20, height: 2))
        horizontalLine.position = CGPoint.zero
        ch.addChild(horizontalLine)

        let verticalLine = SKSpriteNode(color: .white, size: CGSize(width: 2, height: 20))
        verticalLine.position = CGPoint.zero
        ch.addChild(verticalLine)

        let centerDot = SKSpriteNode(color: .red, size: CGSize(width: 3, height: 3))
        centerDot.position = CGPoint.zero
        ch.addChild(centerDot)

        let outlineH = SKSpriteNode(color: .black, size: CGSize(width: 22, height: 4))
        outlineH.position = CGPoint.zero
        outlineH.zPosition = -1
        ch.addChild(outlineH)

        let outlineV = SKSpriteNode(color: .black, size: CGSize(width: 4, height: 22))
        outlineV.position = CGPoint.zero
        outlineV.zPosition = -1
        ch.addChild(outlineV)

        ch.position = CGPoint(x: size.width/2, y: size.height/2)
        addChild(ch)
        crosshair = ch
        #if !os(macOS)
        // On mobile we don't use the mouse-driven crosshair; keep it hidden and use touch aim marker instead.
        crosshair?.isHidden = true
        #endif
    }

    private func setupPhysics() {
        physicsWorld.gravity = CGVector.zero
        physicsWorld.contactDelegate = self
    }

    private func setupDebugLabel() {
        let label = SKLabelNode(fontNamed: "Menlo")
        label.fontSize = 12
        label.fontColor = .white
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .top
        label.position = CGPoint(x: -size.width/2 + 10, y: size.height/2 - 10)
        label.zPosition = 200
        debugRotationLabel = label
        addChild(label)
        updateDebugLabel()
    }

    private func updateDebugLabel() {
        debugRotationLabel?.text = "R: \(debugRotationEnabled ? "ON" : "OFF")  Offset: \(String(format: "%.2f", debugRotationOffset))  (Q/E adjust, R toggle)"
    }

    private func setupInput() {
        // Allow external input (AI) to override default platform input.
        if let ext = externalInput {
            inputController = ext
            // still prepare touch debug visuals for completeness (no-op if macOS)
        } else {
            #if os(macOS)
            inputController = KeyboardMouseInput()
            #else
            inputController = TouchInput(scene: self)
            #endif
        }

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
        knobShape.position = CGPoint(x: leftRegion.position.x + leftRegion.size.width * 0.5, y: leftRegion.position.y + leftRegion.size.height * 0.5)
        // Show touch debug visuals only when running with touch input (mobile player actively playing).
        #if !os(macOS)
        let showDebugNow = (inputController is TouchInput)
        #else
        let showDebugNow = false
        #endif
        knobShape.isHidden = !showDebugNow
        addChild(knobShape)
        debugJoystickKnob = knobShape

        // Aim marker as a single SKShapeNode to avoid any accidental square sprite artifacts.
        // Initially visible only when touch input is active.
        let aimCircle = SKShapeNode(circleOfRadius: 16)
        aimCircle.strokeColor = .red
        aimCircle.lineWidth = 2
        aimCircle.fillColor = SKColor.red.withAlphaComponent(0.12)
        aimCircle.zPosition = 251
        aimCircle.isHidden = !showDebugNow
        aimCircle.position = CGPoint(x: rightRegion.position.x + rightRegion.size.width * 0.5, y: rightRegion.position.y + rightRegion.size.height * 0.5)
        addChild(aimCircle)
        debugAimMarker = aimCircle
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
        crosshair?.position = location
        (inputController as? KeyboardMouseInput)?.mouseMoved(to: location)
        // Safe call: only aim if player exists.
        playerEntity?.aimToward(point: location)
    }

    override func mouseDown(with event: NSEvent) {
        (inputController as? KeyboardMouseInput)?.requestShoot()
    }

    override func mouseEntered(with event: NSEvent) {
        crosshair?.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.unhide()
        NSCursor.arrow.set()
        crosshair?.isHidden = false
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
        // Guard player presence.
        guard let playerEntity = playerEntity else { return }

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
        // Guard player — monsters need a target; skip spawning if player missing.
        guard let playerEntity = playerEntity else { return }

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
        // Guard player presence before updating monsters that target the player.
        guard let playerEntity = playerEntity else { return }

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

        // Safety: if player isn't ready yet (scene not fully initialized) skip this frame.
        guard let playerEntity = playerEntity else { return }

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
        let moveVec = inputController?.movementVector() ?? CGVector(dx: 0, dy: 0)
        playerEntity.move(by: moveVec, deltaTime: deltaTime, sceneSize: size)

        // If using AI input, update it with current monster nodes so AI can aim/shoot.
        if let ai = inputController as? AIInput {
            ai.updateMonsters(monsters.map { $0.sprite })
        }

        // Update debug visuals for touch controls on mobile (left/right regions + joystick knob + aim marker)
        #if !os(macOS)
        // Show debug touch regions when using touch input OR when running menu scripting (AI-driven background).
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
        if let aim = inputController?.aimPoint() {
            crosshair?.position = aim
            playerEntity.aimToward(point: aim)
        }
        #else
        // On mobile: inputController.aimPoint() returns an absolute point computed around the player.
        if let aim = inputController.aimPoint() {
            playerEntity.aimToward(point: aim)
        }
        #endif

        if inputController?.isShooting() ?? false {
            // Prefer aim point if available; on mobile aimPoint() is already oriented around the player.
            let aimPoint = inputController?.aimPoint() ?? crosshair?.position ?? CGPoint.zero
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
