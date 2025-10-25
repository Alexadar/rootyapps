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
            return objc_getAssociatedObject(self, &AssociatedKeys.lastUpdateTime) as? TimeInterval ?? 0
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.lastUpdateTime, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    override func update(_ currentTime: TimeInterval) {
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
            let windowPoint = win.convertPoint(fromScreen: global)
            let pointInView = v.convert(windowPoint, from: nil)
            if !v.bounds.contains(pointInView) {
                NSCursor.unhide()
                NSCursor.arrow.set()
            }
        }
#endif

        // Handle player movement via input controller
        let moveVec = inputController?.movementVector() ?? CGVector(dx: 0, dy: 0)
        playerEntity.move(by: moveVec, deltaTime: deltaTime, sceneSize: size)

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
        if let aim = inputController?.aimPoint() {
            crosshair?.position = aim
            playerEntity.aimToward(point: aim)
        }
        #else
        // On mobile: inputController.aimPoint() returns an absolute point computed around the player.
        if let aim = inputController?.aimPoint() {
            playerEntity.aimToward(point: aim)
        }
        #endif

        if inputController?.isShooting() ?? false {
            // Prefer aim point if available; on mobile aimPoint() is already oriented around the player.
            let aimPoint = inputController?.aimPoint() ?? crosshair?.position ?? CGPoint.zero
            shoot(toward: aimPoint)
        }

        updateMonsters(deltaTime)
        updateDebugLabel()

        if currentTime - lastMonsterSpawn > monsterSpawnInterval {
            spawnMonster()
            lastMonsterSpawn = currentTime
        }

        cleanupBullets()
    }

    func cleanupBullets() {
        bullets.removeAll { bullet in
            if !frame.contains(bullet.sprite.position) {
                bullet.sprite.removeFromParent()
                return true
            }
            return false
        }
    }
}

// Associated Keys for stored properties in extensions
private struct AssociatedKeys {
    static var lastUpdateTime = "lastUpdateTime"
}
