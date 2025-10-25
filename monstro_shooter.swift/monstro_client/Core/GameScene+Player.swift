import SpriteKit

// MARK: - Player & Shooting
extension GameScene {

    func setupPlayer() {
        // Scene uses centered anchor point, so (0, 0) is the center of the screen
        let initialPos = CGPoint(x: 0, y: 0)
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

    func resetPlayer() {
        // Reset player to center of screen
        playerEntity?.sprite.position = CGPoint(x: 0, y: 0)
    }

    func shoot(toward point: CGPoint) {
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
}
