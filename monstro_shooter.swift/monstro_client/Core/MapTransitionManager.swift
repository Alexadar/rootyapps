import SpriteKit

/// Manages animated vertical transitions between maps (TikTok-style)
/// During swipe, both current and incoming maps are visible stacked vertically
class MapTransitionManager {
    weak var scene: GameScene?

    private var incomingWorldLayer: SKNode?
    private(set) var isTransitioning: Bool = false

    // Transition settings
    private let transitionDuration: TimeInterval = 0.35

    init(scene: GameScene) {
        self.scene = scene
    }

    /// Visible viewport height in scene coordinates (accounts for camera zoom)
    private var viewportHeight: CGFloat {
        guard let scene = scene else { return 800 }
        return scene.size.height * GameConstants.cameraScale
    }

    /// Transition to a new map with vertical sliding animation
    /// - Parameters:
    ///   - filename: Map filename to load
    ///   - direction: Swipe direction (.up = next from bottom, .down = previous from top)
    ///   - completion: Called when transition completes with the incoming world node to clean up
    func transitionToMap(_ filename: String, direction: SwipeDirection, completion: @escaping (_ incomingNode: SKNode?) -> Void) {
        guard let scene = scene, !isTransitioning else { return }
        guard let renderer = scene.renderer else { return }

        isTransitioning = true
        print("[MapTransition] Starting transition to \(filename), direction=\(direction)")

        // Freeze game logic (but NOT worldLayer.isPaused so SKActions run)
        scene.isGamePaused = true

        let height = viewportHeight

        // Swipe UP = next map enters from BELOW (positive Y offset in SpriteKit, moves up)
        // Swipe DOWN = previous map enters from ABOVE (negative Y offset in SpriteKit, moves down)
        // SpriteKit Y: positive = up. Camera centered at player position.
        // We slide relative to camera position.
        let incomingOffsetY: CGFloat = direction == .up ? -height : height

        // Create incoming world with tiled background
        let incomingWorld = createWorldLayer()
        incomingWorldLayer = incomingWorld

        // Position incoming world relative to camera (off-screen)
        let cameraY = scene.camera?.position.y ?? 0
        let cameraX = scene.camera?.position.x ?? 0
        incomingWorld.position = CGPoint(x: cameraX, y: cameraY + incomingOffsetY)
        incomingWorld.zPosition = renderer.world.worldLayer.zPosition

        scene.addChild(incomingWorld)

        // Slide distance (same magnitude, opposite direction to bring it on-screen)
        let slideY = -incomingOffsetY

        // Animate current world out
        let currentWorld = renderer.world.worldLayer
        let moveOut = SKAction.moveBy(x: 0, y: slideY, duration: transitionDuration)
        moveOut.timingMode = .easeInEaseOut

        // Animate incoming world in
        let moveIn = SKAction.moveBy(x: 0, y: slideY, duration: transitionDuration)
        moveIn.timingMode = .easeInEaseOut

        currentWorld.run(moveOut)
        incomingWorld.run(moveIn) { [weak self] in
            guard let self = self else { return }
            self.isTransitioning = false
            print("[MapTransition] Animation complete")
            completion(incomingWorld)
        }
    }

    /// Create a world layer with tiled map background (for transition preview)
    private func createWorldLayer() -> SKNode {
        let world = SKNode()
        let mapSize = CGSize(width: 12000, height: 12000)

        guard let texturePath = Bundle.main.path(forResource: "map_background", ofType: "png") else {
            // Fallback solid color
            let fallback = SKSpriteNode(color: .darkGray, size: mapSize)
            fallback.position = .zero
            fallback.zPosition = -10
            world.addChild(fallback)
            return world
        }

        #if os(macOS)
        guard let image = NSImage(contentsOfFile: texturePath) else { return world }
        let texture = SKTexture(image: image)
        #else
        guard let image = UIImage(contentsOfFile: texturePath) else { return world }
        let texture = SKTexture(image: image)
        #endif

        let tileSize = texture.size()
        let tilesX = Int(ceil(mapSize.width / tileSize.width))
        let tilesY = Int(ceil(mapSize.height / tileSize.height))

        let mapContainer = SKNode()
        mapContainer.position = .zero
        mapContainer.zPosition = -10

        for x in 0..<tilesX {
            for y in 0..<tilesY {
                let tile = SKSpriteNode(texture: texture)
                tile.size = tileSize
                let posX = -mapSize.width / 2 + tileSize.width * CGFloat(x) + tileSize.width / 2
                let posY = -mapSize.height / 2 + tileSize.height * CGFloat(y) + tileSize.height / 2
                tile.position = CGPoint(x: posX, y: posY)
                mapContainer.addChild(tile)
            }
        }

        world.addChild(mapContainer)
        return world
    }
}
