import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

class GameScene: SKScene {

    // MARK: - Game Objects
    // Make player optional and guard uses so the scene won't crash if something initialized out-of-order.
    var playerEntity: Player?
    private var gameMap: SKSpriteNode?
    var bullets: [Bullet] = []
    var monsters: [Monster] = []
    var crosshair: SKSpriteNode?
#if os(macOS)
    var trackingArea: NSTrackingArea?
#endif

    // Debug visuals to verify touch control regions (shown only on non-mac platforms)
    var debugLeftRegion: SKSpriteNode?
    var debugRightRegion: SKSpriteNode?
    // Use a generic SKNode for the knob so we can use SKShapeNode (avoid square sprite artifacts).
    var debugJoystickKnob: SKNode?
    var debugAimMarker: SKNode?

    // Input controller (abstracted for future mobile controls)
    var inputController: InputController?
    // Optional external input (e.g. AI) that overrides automatic selection for menu scripting.
    var externalInput: InputController?
    // When true the touch debug regions are shown even if the active input is not TouchInput.
    // Useful for the animated main-menu where we want touch regions visible as an overlay.
    var showTouchDebug: Bool = false

    // MARK: - Game Settings
    let bulletSpeed: CGFloat = 800.0
    var monsterSpawnInterval: TimeInterval = 2.0

    // MARK: - Input / Timing State
    var lastMonsterSpawn: TimeInterval = 0

    // Debug rotation controls (R = toggle auto-apply, Q/E = adjust offset)
    var debugRotationEnabled: Bool = false
    var debugRotationOffset: CGFloat = 0.0
    let debugRotationStep: CGFloat = .pi / 8
    var debugRotationLabel: SKLabelNode?

    // MARK: - Scene Setup
    override func didMove(to view: SKView) {
        setupScene()
        setupMap()
        setupPlayer()
        setupCrosshair()
        setupPhysics()
        setupDebugLabel()
        setupInput()

        // Reset game state to ensure clean start
        resetGame()

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

    func setupScene() {
        // Use center anchor to avoid visible shifting when the SpriteView resizes.
        // This restores the scene coordinate origin to the visual center of the view.
        self.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = .black
        scaleMode = .resizeFill
    }

    func setupMap() {
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

    func setupPhysics() {
        physicsWorld.gravity = CGVector.zero
        physicsWorld.contactDelegate = self
    }

    func setupCrosshair() {
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

    // MARK: - Game Reset
    func resetGame() {
        // Clear all monsters
        for monster in monsters {
            monster.sprite.removeFromParent()
        }
        monsters.removeAll()

        // Clear all bullets
        for bullet in bullets {
            bullet.sprite.removeFromParent()
        }
        bullets.removeAll()

        // Reset player to center
        resetPlayer()

        // Reset spawn timing
        lastMonsterSpawn = 0
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
