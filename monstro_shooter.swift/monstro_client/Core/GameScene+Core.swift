import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

class GameScene: SKScene {

    // MARK: - Renderer
    var renderer: GameRenderer?

    // MARK: - Game Objects
    // Make player optional and guard uses so the scene won't crash if something initialized out-of-order.
    var playerEntity: Player?
    var bullets: [Bullet] = []
    var monsters: [Monster] = []
    var crosshair: SKSpriteNode?
    var gameOverUI: GameOverUI?
    var pauseMenuUI: PauseMenuUI?
#if os(macOS)
    var trackingArea: NSTrackingArea?
#endif

    // MARK: - Level Configuration
    var currentLevel: GameLevel?
    var currentMapSize: CGSize = CGSize(width: 12000, height: 12000)  // Current level map size
    var currentSpawnBoxSize: CGSize = GameConstants.defaultSpawnBoxSize

    // MARK: - Wave Tracking
    var currentWaveIndex: Int = 0
    var levelStartTime: TimeInterval = 0
    var spawnedWaves: Set<Int> = []  // Track which waves have been spawned
    var killCount: Int = 0  // Track killed monsters

    // Input controller (abstracted for future mobile controls)
    var inputController: InputController?
    // Optional external input (e.g. AI) that overrides automatic selection for menu scripting.
    var externalInput: InputController?

    // MARK: - Game Settings
    var monsterSpawnInterval: TimeInterval = GameConstants.defaultMonsterSpawnInterval

    // MARK: - Game State
    var isGameOver: Bool = false
    var isGamePaused: Bool = false
    var onReturnToMenu: (() -> Void)?

    // MARK: - Damage System
    var touchingMonsters: Set<ObjectIdentifier> = []  // Monsters currently touching player
    var lastDamageTime: TimeInterval = 0
    var damageInterval: TimeInterval = 1.0  // Damage every 1 second

    // MARK: - Input / Timing State
    var lastMonsterSpawn: TimeInterval = 0

    // Debug rotation controls (R = toggle auto-apply, Q/E = adjust offset)
    var debugRotationEnabled: Bool = false
    var debugRotationOffset: CGFloat = 0.0
    var debugRotationLabel: SKLabelNode?

    // MARK: - Scene Setup
    override func didMove(to view: SKView) {
        setupScene()
        setupRenderer()
        setupPlayer()
        setupCrosshair()
        setupPhysics()
        setupDebugLabel()
        setupInput()
        setupPauseMenu()

        // Load level from settings
        let mapFilename = SettingsManager.shared.selectedMapFilename
        print("[GameScene] Loading map: \(mapFilename)")
        if let mapConfig = MapConfig.load(filename: mapFilename) {
            print("[GameScene] Loaded MapConfig: \(mapConfig.getLocalizedName()), monsters: \(mapConfig.monsterTypes)")
            let level = convertMapConfigToLevel(mapConfig)
            loadLevel(level)
        } else {
            print("[GameScene] Failed to load \(mapFilename), using fallback level")
            // Fallback to hardcoded test level
            if let testLevel = LevelManager.shared.getLevel(id: 1) {
                loadLevel(testLevel)
            }
        }

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

    func setupRenderer() {
        // Create and setup renderer with current map size
        renderer = GameRenderer(scene: self, mapSize: currentMapSize)
        renderer?.setup()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Handle viewport changes through renderer
        if let view = view {
            renderer?.handleViewportChange(view.bounds.size)
        }

        // Debug visuals are now managed by InputController - no need to update here

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
        ch.zPosition = 1000 // Above HUD layer (HUD is 100)

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

        ch.position = CGPoint.zero  // Will be updated by mouse position
        // Add crosshair to camera (UI layer, not world layer)
        camera?.addChild(ch)
        crosshair = ch
        #if !os(macOS)
        // On mobile we don't use the mouse-driven crosshair; keep it hidden and use touch aim marker instead.
        crosshair?.isHidden = true
        #endif
    }

    // MARK: - Level Management

    /// Convert MapConfig JSON to GameLevel
    private func convertMapConfigToLevel(_ config: MapConfig) -> GameLevel {
        // Build spawn waves from JSON data
        var waves: [SpawnWave] = []

        print("[convertMapConfigToLevel] Processing \(config.monsterSpawnWaves.count) spawn waves")

        let monsterNames = config.monsterTypes.map { period in
            let names = period.monsterTypeIds.compactMap { id in
                GameConstants.MonsterType(rawValue: id)?.name ?? "\(id)"
            }.joined(separator: ", ")
            return "t:\(period.startTime) [\(names)]"
        }
        print("[convertMapConfigToLevel] Monster type periods: \(monsterNames)")

        for spawnWave in config.monsterSpawnWaves {
            // Find all monster types available at any time
            let allAvailableTypes = config.monsterTypes.flatMap { $0.monsterTypeIds }

            let availableNames = allAvailableTypes.compactMap { id in
                GameConstants.MonsterType(rawValue: id)?.name ?? "\(id)"
            }.joined(separator: ", ")

            print("[convertMapConfigToLevel] Wave at t=\(spawnWave.startTime), count=\(spawnWave.count), monsters: [\(availableNames)]")

            if spawnWave.count > 0 && !allAvailableTypes.isEmpty {
                waves.append(SpawnWave(
                    startTime: TimeInterval(spawnWave.startTime),
                    monsterCount: spawnWave.count,
                    monsterTypeIDs: allAvailableTypes,
                    spawnInterval: 1.0
                ))
            }
        }

        return GameLevel(
            id: config.id,
            name: config.getLocalizedName(),
            description: config.getLocalizedDescription(),
            orderNumber: config.orderNumber,
            difficulty: 5,
            duration: TimeInterval(config.landingDuration),
            mapSize: CGSize(width: 12000, height: 12000),
            spawnWaves: waves
        )
    }

    func loadLevel(_ level: GameLevel) {
        currentLevel = level
        currentMapSize = level.mapSize
        currentSpawnBoxSize = level.spawnBoxSize

        // Update world map size in renderer
        renderer?.world.updateMapSize(level.mapSize)

        // Reset wave tracking
        currentWaveIndex = 0
        spawnedWaves.removeAll()
        levelStartTime = 0  // Will be set on first update

        let mapFilename = SettingsManager.shared.selectedMapFilename
        let allMonsterTypeIDs = Set(level.spawnWaves.flatMap { $0.monsterTypeIDs }).sorted()
        print("Loaded level: \(level.name) (file: \(mapFilename)) - Map: \(level.mapSize.width)x\(level.mapSize.height), Waves: \(level.spawnWaves.count), Monster IDs: \(allMonsterTypeIDs.map { String($0) }.joined(separator: ", "))")
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

        // Reset wave tracking
        currentWaveIndex = 0
        spawnedWaves.removeAll()
        levelStartTime = 0
        killCount = 0

        // Reset damage tracking
        touchingMonsters.removeAll()
        lastDamageTime = 0

        // Reset player health
        playerEntity?.health = 100
    }

    // MARK: - Game Over
    func handlePlayerDeath() {
        guard !isGameOver else { return }
        isGameOver = true

        print("Player died! Game over.")

        // Don't pause scene, just stop game logic via isGameOver flag

        // Show game over UI
        showGameOverUI()
    }

    func showGameOverUI() {
        // Hide debug visuals via input controller
        inputController?.hideDebugVisuals()

        // Create game over UI if needed
        if gameOverUI == nil {
            gameOverUI = GameOverUI(scene: self)
        }

        // Show game over UI
        gameOverUI?.show(
            onTryAgain: { [weak self] in
                self?.restartGame()
            },
            onGoToMenu: { [weak self] in
                self?.returnToMenu()
            }
        )
    }

    func restartGame() {
        isGameOver = false
        gameOverUI?.hide()

        // Show debug visuals via input controller
        inputController?.showDebugVisuals()

        resetGame()
    }

    func returnToMenu() {
        // Trigger SwiftUI dismiss via closure on main thread
        onReturnToMenu?()
        // Play menu music after triggering dismiss
        AudioManager.shared.playMenuMusic()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
