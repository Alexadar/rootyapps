import SpriteKit

// MARK: - Camera Management
extension GameScene {

    /// Setup camera for the scene
    func setupCamera() {
        let camera = SKCameraNode()
        self.camera = camera
        addChild(camera)

        // Position camera at scene center initially
        camera.position = CGPoint(x: 0, y: 0)
    }

    /// Update camera to follow player with smooth interpolation
    /// Camera is bounded by map size and uses device viewport
    func updateCamera(mapSize: CGSize) {
        guard let camera = self.camera, let player = playerEntity else { return }

        let playerPos = player.sprite.position
        let currentCameraPos = camera.position

        // Smooth camera follow using linear interpolation (lerp)
        // Lower smoothing value = smoother/slower follow
        let smoothing = GameConstants.cameraFollowSmoothing
        let targetX = currentCameraPos.x + (playerPos.x - currentCameraPos.x) * smoothing
        let targetY = currentCameraPos.y + (playerPos.y - currentCameraPos.y) * smoothing

        // Calculate camera bounds based on map size and viewport
        // The camera should not show area beyond the map boundaries
        let viewportSize = size  // Device viewport size (e.g., 1024x768 or actual device size)

        // Map boundaries (in scene coordinates with centered anchor)
        let mapMinX = -mapSize.width / 2
        let mapMaxX = mapSize.width / 2
        let mapMinY = -mapSize.height / 2
        let mapMaxY = mapSize.height / 2

        // Calculate camera limits (camera center shouldn't go beyond these to keep viewport inside map)
        // This ensures the camera edges never slide beyond map edges
        let cameraMinX = mapMinX + viewportSize.width / 2
        let cameraMaxX = mapMaxX - viewportSize.width / 2
        let cameraMinY = mapMinY + viewportSize.height / 2
        let cameraMaxY = mapMaxY - viewportSize.height / 2

        // Handle cases where viewport is larger than map (center camera)
        let finalX: CGFloat
        let finalY: CGFloat

        if mapSize.width <= viewportSize.width {
            // Map width is smaller than viewport, center horizontally
            finalX = 0
        } else {
            // Clamp camera X to keep edges inside map
            finalX = max(cameraMinX, min(cameraMaxX, targetX))
        }

        if mapSize.height <= viewportSize.height {
            // Map height is smaller than viewport, center vertically
            finalY = 0
        } else {
            // Clamp camera Y to keep edges inside map
            finalY = max(cameraMinY, min(cameraMaxY, targetY))
        }

        camera.position = CGPoint(x: finalX, y: finalY)

        // Update HUD to follow camera
        gameHUD?.updatePosition(cameraPosition: camera.position)
    }
}
