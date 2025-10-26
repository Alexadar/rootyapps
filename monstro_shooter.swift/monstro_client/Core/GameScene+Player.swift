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
            // Add player to world layer instead of scene
            renderer?.world.worldLayer.addChild(p.sprite)
        }
    }

    func resetPlayer() {
        // Reset player to center of screen
        playerEntity?.sprite.position = CGPoint(x: 0, y: 0)
    }

    func shoot(toward point: CGPoint, currentTime: TimeInterval) {
        // Guard player presence.
        guard let playerEntity = playerEntity else { return }

        // Calculate angle to target
        let dx = point.x - playerEntity.sprite.position.x
        let dy = point.y - playerEntity.sprite.position.y
        let angle = atan2(dy, dx)

        // Try to fire weapon
        guard let bulletInfos = playerEntity.currentWeapon.fire(at: currentTime, baseAngle: angle) else {
            return  // Can't fire (reloading, out of ammo, rate limit)
        }

        // Create bullets from weapon and add to world layer
        for bulletInfo in bulletInfos {
            let bullet = Bullet.create(at: playerEntity.sprite.position, angle: angle, bulletInfo: bulletInfo)
            renderer?.world.worldLayer.addChild(bullet.sprite)
            bullets.append(bullet)
        }

        // Play weapon sound effect
        let soundName = playerEntity.currentWeapon.config.weaponSoundName
        if soundName == "weapon_pistol" {
            AudioManager.shared.playPistolSound()
        }
        // TODO: Add rifle/minigun sounds when available
    }
}
