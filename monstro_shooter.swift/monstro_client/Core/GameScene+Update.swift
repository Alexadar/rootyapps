import SpriteKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Game Loop & Updates
extension GameScene {

    // MARK: - Game Loop
    private var lastUpdateTime: TimeInterval {
        get {
            return objc_getAssociatedObject(self, AssociatedKeys.lastUpdateTimeKey) as? TimeInterval ?? 0
        }
        set {
            objc_setAssociatedObject(self, AssociatedKeys.lastUpdateTimeKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    override func update(_ currentTime: TimeInterval) {
        // Skip update if game over or paused
        guard !isGameOver else { return }
        guard !isGamePaused else { return }

        let deltaTime: TimeInterval
        if lastUpdateTime > 0 {
            deltaTime = currentTime - lastUpdateTime
        } else {
            deltaTime = 0
        }
        lastUpdateTime = currentTime

        // Safety: if player isn't ready yet (scene not fully initialized) skip this frame.
        guard let playerEntity = playerEntity else { return }

        // Handle player movement via input controller
        let moveVec = inputController?.movementVector() ?? CGVector(dx: 0, dy: 0)
        playerEntity.move(by: moveVec, deltaTime: deltaTime, mapSize: currentMapSize)

        // Track movement for tutorial
        if moveVec.dx != 0 || moveVec.dy != 0 {
            tutorialController?.recordMove(at: currentTime)
        }

        // Update debug visuals via input controller
        inputController?.updateDebugVisuals(movementVector: moveVec, aimPoint: inputController?.aimPoint())

        // Aim and shooting
        #if os(macOS)
        // Crosshair position is in camera space (view coordinates), already set by input controller
        if let aimCameraCoords = inputController?.aimPoint() {
            crosshair?.position = aimCameraCoords

            // Convert camera coords to world coords for player aiming
            if let cam = camera {
                let worldCoords = CGPoint(
                    x: aimCameraCoords.x + cam.position.x,
                    y: aimCameraCoords.y + cam.position.y
                )
                playerEntity.aimToward(point: worldCoords)
            }
        }
        #else
        // On mobile: inputController.aimPoint() returns an absolute point computed around the player.
        if let aim = inputController?.aimPoint() {
            playerEntity.aimToward(point: aim)
        }
        #endif

        if inputController?.isShooting() ?? false {
            // Get aim point in world coordinates for bullet trajectory
            #if os(macOS)
            if let aimCameraCoords = inputController?.aimPoint(), let cam = camera {
                let worldCoords = CGPoint(
                    x: aimCameraCoords.x + cam.position.x,
                    y: aimCameraCoords.y + cam.position.y
                )
                shoot(toward: worldCoords, currentTime: currentTime)
            }
            #else
            let aimPoint = inputController?.aimPoint() ?? CGPoint.zero
            shoot(toward: aimPoint, currentTime: currentTime)
            #endif
        }

        // Update player weapon (reload progress)
        playerEntity.currentWeapon.update(currentTime: currentTime)

        updateMonsters(deltaTime)
        updateBullets(deltaTime)
        updateMonsterDamage(currentTime: currentTime)
        updateDebugLabel()
        updateHUD(currentTime: currentTime)

        // Process wave-based spawning from current level
        processWaveSpawning(currentTime: currentTime)

        cleanupBullets()

        // Update camera to follow player (with map bounds)
        updateCamera(mapSize: currentMapSize)

        // Update tutorial hints
        tutorialController?.update(currentTime: currentTime)
    }

    func updateHUD(currentTime: TimeInterval) {
        // Update time counter (elapsed time since level start)
        if levelStartTime > 0 {
            let elapsedTime = Int(currentTime - levelStartTime)
            renderer?.updateTime(seconds: elapsedTime)
        }

        // Update all HUD elements from player
        if let player = playerEntity {
            // Update kill counter
            renderer?.updateKills(count: killCount)

            // Update ammo
            let weapon = player.currentWeapon
            let totalAmmo = weapon.currentAmmo + (weapon.config.magazineSize * 10) // Estimate total reserve
            renderer?.updateAmmo(current: weapon.currentAmmo, total: totalAmmo)

            // Update health
            renderer?.updateHealth(value: player.health)
        }
    }

    func updateBullets(_ deltaTime: TimeInterval) {
        for bullet in bullets {
            bullet.update(deltaTime: deltaTime)
        }
    }

    func cleanupBullets() {
        bullets.removeAll { bullet in
            // Remove if expired (out of range or hit limit)
            if bullet.isExpired() {
                bullet.sprite.removeFromParent()
                return true
            }
            // Remove if far from camera (not just scene frame)
            if let camera = self.camera {
                let dx = bullet.sprite.position.x - camera.position.x
                let dy = bullet.sprite.position.y - camera.position.y
                let distance = sqrt(dx*dx + dy*dy)
                if distance > 2000 {  // Far offscreen
                    bullet.sprite.removeFromParent()
                    return true
                }
            }
            return false
        }
    }
}

// Associated Keys for stored properties in extensions
private struct AssociatedKeys {
    static let lastUpdateTimeKey: UnsafeRawPointer = {
        let key = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        key.initialize(to: 0)
        return UnsafeRawPointer(key)
    }()
}
