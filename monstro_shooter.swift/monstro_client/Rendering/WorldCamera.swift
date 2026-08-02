import SpriteKit

/// Camera that follows the player in the game world
class WorldCamera {
    let cameraNode: SKCameraNode
    private weak var scene: SKScene?

    init(scene: SKScene) {
        self.scene = scene
        self.cameraNode = SKCameraNode()
        self.cameraNode.position = CGPoint.zero
        self.cameraNode.setScale(GameConstants.cameraScale)
    }

    /// Update camera to follow target with smooth interpolation
    /// Camera is bounded by map size and uses device viewport
    func followTarget(position: CGPoint, mapSize: CGSize, viewportSize: CGSize) {
        // Clamp/lerp math lives in CameraMath so it can be unit-tested without an SKScene.
        cameraNode.position = CameraMath.clampedPosition(
            target: position,
            current: cameraNode.position,
            mapSize: mapSize,
            viewportSize: viewportSize,
            smoothing: GameConstants.cameraFollowSmoothing
        )
    }
}
