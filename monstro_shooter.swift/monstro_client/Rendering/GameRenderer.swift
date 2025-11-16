import SpriteKit

/// Master renderer that manages rendering hierarchy:
/// renderer.camera.contains(hud), renderer.world.contains(gameplay)
/// Provides clean separation between UI and game world layers
///
/// **Rendering Architecture:**
/// ```
/// SKScene
///   ├── world.worldLayer (zPosition: 0) - PAUSABLE game layer
///   │   ├── map background (zPosition: -10)
///   │   ├── player sprite
///   │   ├── monster sprites
///   │   └── bullet sprites
///   └── worldCamera.cameraNode (scene.camera) - ALWAYS ACTIVE
///       ├── hudCamera.hudLayer - UI elements
///       │   ├── time panel
///       │   ├── health panel
///       │   ├── ammo panel
///       │   └── kills panel
///       └── pauseMenu (added directly to camera) - UI overlay
/// ```
///
/// **Pause System:**
/// - Pausing `world.worldLayer.isPaused = true` freezes ALL gameplay
/// - Camera layer remains active for UI interaction (HUD, pause menu)
/// - This separation is critical for responsive pause menus
class GameRenderer {
    // Rendering components
    let worldCamera: WorldCamera
    let hudCamera: HUDCamera
    let world: GameWorld  // Contains worldLayer - pause this to freeze game

    private weak var scene: SKScene?

    init(scene: SKScene, mapSize: CGSize) {
        self.scene = scene

        // Create world camera (follows player)
        self.worldCamera = WorldCamera(scene: scene)

        // Create HUD camera (isolated layer that follows world camera)
        self.hudCamera = HUDCamera(worldCamera: worldCamera)

        // Create game world (contains all gameplay elements)
        self.world = GameWorld(scene: scene, mapSize: mapSize)
    }

    /// Initialize renderer components in scene
    func setup() {
        guard let scene = scene else { return }

        // Add world layer to scene
        scene.addChild(world.worldLayer)

        // Setup world map
        world.setupMap()

        // Add camera to scene and set as active
        scene.addChild(worldCamera.cameraNode)
        scene.camera = worldCamera.cameraNode

        // Add HUD layer to camera (HUD follows camera)
        worldCamera.cameraNode.addChild(hudCamera.hudLayer)

        // Setup HUD elements
        if let view = scene.view {
            hudCamera.setup(viewportSize: view.bounds.size)
        }
    }

    /// Update renderer (called every frame)
    func update(playerPosition: CGPoint, viewportSize: CGSize) {
        // Update world camera to follow player
        worldCamera.followTarget(
            position: playerPosition,
            mapSize: world.currentMapSize,
            viewportSize: viewportSize
        )

        // Update HUD position to stay in viewport
        hudCamera.updatePosition()
    }

    /// Handle viewport size changes
    func handleViewportChange(_ newSize: CGSize) {
        hudCamera.repositionForViewport(newSize)
    }

    /// Update HUD time display
    func updateTime(seconds: Int) {
        hudCamera.updateTime(seconds: seconds)
    }

    /// Update HUD kills counter
    func updateKills(count: Int) {
        hudCamera.updateKills(count: count)
    }

    /// Update HUD ammo display
    func updateAmmo(current: Int, total: Int) {
        hudCamera.updateAmmo(current: current, total: total)
    }

    /// Update HUD health display
    func updateHealth(value: Int) {
        hudCamera.updateHealth(value: value)
    }
}
