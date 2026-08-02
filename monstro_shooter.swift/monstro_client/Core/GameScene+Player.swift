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

    /// Load and apply weapon and exoskeleton from GameConfig
    func applyLoadoutFromSettings() {
        guard let player = playerEntity else { return }

        let config = GameConfig.current

        // Load weapon from config
        if let weaponConfig = WeaponManager.shared.getWeapon(id: config.weaponId) {
            player.currentWeapon = Weapon(config: weaponConfig)
            print("[GameScene] Applied weapon: \(weaponConfig.name)")
        } else {
            print("[GameScene] Warning: Could not find weapon with ID \(config.weaponId), using default")
        }

        // Load exoskeleton from config
        if let exoskeletonConfig = ExoskeletonManager.shared.getExoskeleton(id: config.exoskeletonId) {
            player.applyExoskeleton(exoskeletonConfig)
            print("[GameScene] Applied exoskeleton: \(exoskeletonConfig.name)")
        } else {
            print("[GameScene] Warning: Could not find exoskeleton with ID \(config.exoskeletonId), using default")
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
        // Use player sprite's rotation directly - it already faces the cursor correctly
        // This accounts for player movement and is updated every frame
        // Player sprite has -90° offset because sprite faces UP, add it back for bullet direction
        let baseAngle = playerEntity.sprite.zRotation + (.pi / 2)

        for bulletInfo in bulletInfos {
            // Apply angular deviation perpendicular to aim direction
            // deviation is max spread in pixels at some reference distance
            // Convert to angular spread: at 500px distance, deviation pixels = angle radians approx
            let angularDeviation = SpreadMath.deviationToAngle(bulletInfo.deviation) // Convert pixel deviation to angle
            let randomSpread = CGFloat.random(in: -angularDeviation...angularDeviation)
            let finalAngle = baseAngle + randomSpread

            let bullet = Bullet.create(at: playerPos, angle: finalAngle, bulletInfo: bulletInfo)
            renderer?.world.worldLayer.addChild(bullet.sprite)
            bullets.append(bullet)
        }

        // Play weapon sound effect
        AudioManager.shared.playWeaponSound(playerEntity.currentWeapon.config.weaponSoundName)

        // Track shooting for tutorial
        tutorialController?.recordShoot(at: currentTime)
    }
}
