import SpriteKit

/// Camera that follows the player in the game world
class WorldCamera {
    let cameraNode: SKCameraNode
    private weak var scene: SKScene?

    init(scene: SKScene) {
        self.scene = scene
        self.cameraNode = SKCameraNode()
        self.cameraNode.position = CGPoint.zero
    }

    /// Update camera to follow target with smooth interpolation
    /// Camera is bounded by map size and uses device viewport
    func followTarget(position: CGPoint, mapSize: CGSize, viewportSize: CGSize) {
        let currentPos = cameraNode.position

        // Smooth camera follow using linear interpolation
        let smoothing = GameConstants.cameraFollowSmoothing
        let targetX = currentPos.x + (position.x - currentPos.x) * smoothing
        let targetY = currentPos.y + (position.y - currentPos.y) * smoothing

        // Map boundaries (in scene coordinates with centered anchor)
        let mapMinX = -mapSize.width / 2
        let mapMaxX = mapSize.width / 2
        let mapMinY = -mapSize.height / 2
        let mapMaxY = mapSize.height / 2

        // Calculate camera limits (camera center shouldn't go beyond these to keep viewport inside map)
        let cameraMinX = mapMinX + viewportSize.width / 2
        let cameraMaxX = mapMaxX - viewportSize.width / 2
        let cameraMinY = mapMinY + viewportSize.height / 2
        let cameraMaxY = mapMaxY - viewportSize.height / 2

        // Handle cases where viewport is larger than map (center camera)
        let finalX: CGFloat
        let finalY: CGFloat

        if mapSize.width <= viewportSize.width {
            finalX = 0
        } else {
            finalX = max(cameraMinX, min(cameraMaxX, targetX))
        }

        if mapSize.height <= viewportSize.height {
            finalY = 0
        } else {
            finalY = max(cameraMinY, min(cameraMaxY, targetY))
        }

        cameraNode.position = CGPoint(x: finalX, y: finalY)
    }
}
