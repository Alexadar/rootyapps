import SpriteKit

// MARK: - Camera Management
// Camera is now managed by GameRenderer
extension GameScene {

    /// Update camera to follow player with smooth interpolation
    /// Delegated to renderer which manages camera hierarchy
    func updateCamera(mapSize: CGSize) {
        guard let player = playerEntity, let view = view else { return }
        renderer?.update(playerPosition: player.sprite.position, viewportSize: view.bounds.size)
    }
}
