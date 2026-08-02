import SpriteKit

/// Contains all gameplay elements (player, monsters, bullets, map)
/// Managed by the renderer and isolated from UI layer
///
/// **Pause System Architecture:**
/// - worldLayer is the ONLY node that gets paused via worldLayer.isPaused = true
/// - When paused, ALL children (player, monsters, bullets, map) stop:
///   - SKActions stop executing
///   - Physics simulation stops
///   - Manual update() loop is blocked by guard in GameScene+Update
/// - UI elements (HUD, pause menu) live in cameraNode layer and remain active
/// - This follows SpriteKit best practice: pause game world, keep UI interactive
class GameWorld {
    /// Master container for all gameplay elements
    /// PAUSE THIS NODE to freeze player, monsters, bullets, physics
    let worldLayer: SKNode

    private weak var scene: SKScene?

    // Game elements
    private var gameMap: SKSpriteNode?
    var currentMapSize: CGSize

    init(scene: SKScene, mapSize: CGSize) {
        self.scene = scene
        self.currentMapSize = mapSize
        self.worldLayer = SKNode()
        self.worldLayer.zPosition = 0  // World is at base layer
    }

    /// Create tiled map background
    func setupMap() {
        let mapTexturePath = Bundle.main.path(forResource: "map_background", ofType: "png")

        if let texturePath = mapTexturePath {
            #if os(macOS)
            if let nsImage = NSImage(contentsOfFile: texturePath) {
                let texture = SKTexture(image: nsImage)
                createTiledMap(texture: texture)
            } else {
                createFallbackMap()
            }
            #else
            if let uiImage = UIImage(contentsOfFile: texturePath) {
                let texture = SKTexture(image: uiImage)
                createTiledMap(texture: texture)
            } else {
                createFallbackMap()
            }
            #endif
        } else {
            createFallbackMap()
        }
    }

    private func createTiledMap(texture: SKTexture) {
        let tileSize = texture.size()

        // Calculate how many tiles needed
        let tilesX = Int(ceil(currentMapSize.width / tileSize.width))
        let tilesY = Int(ceil(currentMapSize.height / tileSize.height))

        // Create parent node to hold all tiles
        let mapContainer = SKNode()
        mapContainer.position = CGPoint.zero
        mapContainer.zPosition = -10

        // Tile the texture across the map
        for x in 0..<tilesX {
            for y in 0..<tilesY {
                let tile = SKSpriteNode(texture: texture)
                tile.size = tileSize

                // Position tiles from center anchor
                let posX = -currentMapSize.width / 2 + tileSize.width * CGFloat(x) + tileSize.width / 2
                let posY = -currentMapSize.height / 2 + tileSize.height * CGFloat(y) + tileSize.height / 2
                tile.position = CGPoint(x: posX, y: posY)

                mapContainer.addChild(tile)
            }
        }

        worldLayer.addChild(mapContainer)

        // Store reference using a colored sprite for compatibility
        gameMap = SKSpriteNode(color: .clear, size: currentMapSize)
        gameMap?.position = CGPoint.zero
        gameMap?.zPosition = -10
    }

    private func createFallbackMap() {
        gameMap = SKSpriteNode(color: .darkGray, size: currentMapSize)
        gameMap?.position = CGPoint.zero
        gameMap?.zPosition = -10
        if let gm = gameMap {
            worldLayer.addChild(gm)
        }
    }

    /// Update map size (when level changes)
    func updateMapSize(_ newSize: CGSize) {
        currentMapSize = newSize
        gameMap?.size = newSize
    }
}
