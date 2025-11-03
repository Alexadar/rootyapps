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

            // Apply selected weapon and exoskeleton from settings
            applyLoadoutFromSettings()
        }
    }

    /// Load and apply weapon and exoskeleton selections from SettingsManager
    func applyLoadoutFromSettings() {
        guard let player = playerEntity else { return }

        // Load selected weapon
        let weaponId = SettingsManager.shared.selectedWeaponId
        if let weaponConfig = WeaponManager.shared.getWeapon(id: weaponId) {
            player.currentWeapon = Weapon(config: weaponConfig)
            print("[GameScene] Applied weapon: \(weaponConfig.name)")
        } else {
            print("[GameScene] Warning: Could not find weapon with ID \(weaponId), using default")
        }

        // Load selected exoskeleton
        let exoskeletonId = SettingsManager.shared.selectedExoskeletonId
        if let exoskeletonConfig = ExoskeletonManager.shared.getExoskeleton(id: exoskeletonId) {
            player.applyExoskeleton(exoskeletonConfig)
            print("[GameScene] Applied exoskeleton: \(exoskeletonConfig.name)")
        } else {
            print("[GameScene] Warning: Could not find exoskeleton with ID \(exoskeletonId), using default")
        }
    }

    func resetPlayer() {
        // Reset player to center of screen
        playerEntity?.sprite.position = CGPoint(x: 0, y: 0)
    }

    func shoot(toward point: CGPoint, currentTime: TimeInterval) {
        // Guard player presence.
        guard let playerEntity = playerEntity else { return }

        // Try to fire weapon (baseAngle not used anymore, deviation calculated per bullet)
        guard let bulletInfos = playerEntity.currentWeapon.fire(at: currentTime, baseAngle: 0) else {
            return  // Can't fire (reloading, out of ammo, rate limit)
        }

        // Create bullets from weapon and add to world layer
        let playerPos = playerEntity.sprite.position
        for bulletInfo in bulletInfos {
            // Apply deviation to target point (old game method)
            // var deviation:Point = Point.polar(currentDeviation * Math.random(), Math.PI * Math.random())
            let deviationRadius = CGFloat.random(in: 0...bulletInfo.deviation)
            let deviationAngle = CGFloat.random(in: 0...(.pi * 2))
            let deviationX = deviationRadius * cos(deviationAngle)
            let deviationY = deviationRadius * sin(deviationAngle)

            let targetWithDeviation = CGPoint(
                x: point.x + deviationX,
                y: point.y + deviationY
            )

            // Calculate angle to deviated target
            let dx = targetWithDeviation.x - playerPos.x
            let dy = targetWithDeviation.y - playerPos.y
            let angle = atan2(dy, dx)

            let bullet = Bullet.create(at: playerPos, angle: angle, bulletInfo: bulletInfo)
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
