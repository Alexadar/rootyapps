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
        // Skip update if game over
        if isGameOver { return }

        let deltaTime: TimeInterval
        if lastUpdateTime > 0 {
            deltaTime = currentTime - lastUpdateTime
        } else {
            deltaTime = 0
        }
        lastUpdateTime = currentTime

        // Safety: if player isn't ready yet (scene not fully initialized) skip this frame.
        guard let playerEntity = playerEntity else { return }

        // Safety: restore cursor if outside view bounds
#if os(macOS)
        if let win = view?.window, let v = view {
            let global = NSEvent.mouseLocation
            let windowRect = NSRect(origin: NSPoint(x: global.x, y: global.y), size: .zero)
            let convertedRect = win.convertFromScreen(windowRect)
            let pointInView = v.convert(convertedRect.origin, from: nil)
            if !v.bounds.contains(pointInView) {
                NSCursor.unhide()
                NSCursor.arrow.set()
            }
        }
#endif

        // Handle player movement via input controller
        let moveVec = inputController?.movementVector() ?? CGVector(dx: 0, dy: 0)
        playerEntity.move(by: moveVec, deltaTime: deltaTime, mapSize: currentMapSize)

        // If using AI input, update it with current monster nodes so AI can aim/shoot.
        if let ai = inputController as? AIInput {
            ai.updateMonsters(monsters.map { $0.sprite })
        }

        // Update debug visuals for touch controls on mobile (left/right regions + joystick knob + aim marker)
        #if !os(macOS)
        // Show debug touch regions when using touch input OR when running menu scripting (AI-driven background).
        if inputController is TouchInput {
            // Joystick knob: center in left region and offset by movement vector scaled by joystick radius
            if let knob = debugJoystickKnob, let leftRegion = debugLeftRegion {
                // Center of left control region
                let center = CGPoint(x: leftRegion.position.x + leftRegion.size.width * 0.5, y: leftRegion.position.y + leftRegion.size.height * 0.5)
                let radius: CGFloat = 60.0
                // Always show knob; when movement vector is zero it stays at the region center.
                knob.isHidden = false
                knob.position = CGPoint(x: center.x + moveVec.dx * radius, y: center.y + moveVec.dy * radius)
            }

            // Aim marker: if player is actively aiming use computed aim point (scene coords),
            // otherwise show the right control area's center so the circle remains visible.
            if let aimMarker = debugAimMarker, let rightRegion = debugRightRegion {
                if let aim = inputController?.aimPoint() {
                    aimMarker.position = aim
                } else {
                    // Right region center in scene coords
                    let rightCenter = CGPoint(x: rightRegion.position.x + rightRegion.size.width * 0.5, y: rightRegion.position.y + rightRegion.size.height * 0.5)
                    aimMarker.position = rightCenter
                }
                aimMarker.isHidden = false
            }
        } else {
            // Hide debug visuals if not using touch input
            debugJoystickKnob?.isHidden = true
            debugAimMarker?.isHidden = true
        }
        #endif

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
