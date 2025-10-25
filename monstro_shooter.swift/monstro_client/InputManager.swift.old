import Foundation
import CoreGraphics
#if os(macOS)
import AppKit
#else
import UIKit
import SpriteKit
#endif

/// macOS keyboard + mouse input controller.
/// GameScene forwards NSEvent callbacks to this object which implements InputController.
/// Designed so we can later add a touch-based implementation for mobile platforms.
#if os(macOS)
class KeyboardMouseInput: InputController {
    private var keysPressed = Set<UInt16>()
    private var mouseLocation: CGPoint? = nil
    private var shootRequested = false

    // Keycodes used in original project (macOS):
    // W:13, A:0, S:1, D:2
    private let keyW: UInt16 = 13
    private let keyA: UInt16 = 0
    private let keyS: UInt16 = 1
    private let keyD: UInt16 = 2

    init() {}

    // Methods for GameScene to forward platform events:
    func keyDown(_ event: NSEvent) {
        keysPressed.insert(event.keyCode)
    }

    func keyUp(_ event: NSEvent) {
        keysPressed.remove(event.keyCode)
    }

    func mouseMoved(to location: CGPoint) {
        mouseLocation = location
    }

    /// Called when mouse/touch firing input occurs. This is an edge-trigger: isShooting()
    /// will return true once after this call and then reset until next call.
    func requestShoot() {
        shootRequested = true
    }

    func mouseEntered() {
        // keep mouseLocation if needed, nothing special for now
    }

    func mouseExited() {
        // keep mouseLocation if needed, nothing special for now
    }

    // InputController conformance
    func movementVector() -> CGVector {
        var v = CGVector(dx: 0, dy: 0)
        if keysPressed.contains(keyW) { v.dy += 1 }
        if keysPressed.contains(keyS) { v.dy -= 1 }
        if keysPressed.contains(keyA) { v.dx -= 1 }
        if keysPressed.contains(keyD) { v.dx += 1 }
        return v
    }

    func aimPoint() -> CGPoint? {
        return mouseLocation
    }

    func isShooting() -> Bool {
        if shootRequested {
            shootRequested = false
            return true
        }
        return false
    }
}
#endif

// Touch-based input for mobile (iOS/tvOS)
/*
Design:
- Landscape layout assumed.
- Left half of the screen acts as a virtual joystick for movement:
  * On touch begin within left half, it'll become "leftTouch" and set a joystick origin.
  * Dragging updates movement vector in range -1..1 based on joystick radius.
- Right half of the screen is for aiming and shooting:
  * Touching the right half becomes "rightTouch". While held, aimPoint() returns that location
    and isShooting() returns true (continuous firing while holding).
  * Moving the right touch updates aim position.
This class is only compiled for non-macOS platforms.
*/
#if !os(macOS)
class TouchInput: InputController {
    private weak var scene: SKScene?

    // Track two touches: left (movement) and right (aim/shoot)
    private var leftTouch: UITouch?
    private var rightTouch: UITouch?

    // Joystick state for the left touch
    private var leftOrigin: CGPoint = .zero
    private var leftCurrent: CGPoint?

    // Last raw touch position for right touch (scene coords)
    private var rightRawPosition: CGPoint?

    // Virtual origin for right-side aiming area (center of right half region).
    // When a right touch begins we anchor the aim joystick origin to this center so the
    // finger->origin vector defines the aim direction that's then mapped relative to the player.
    private var rightOrigin: CGPoint?

    // Joystick sensitivity / radius for both virtual sticks
    private let joystickRadius: CGFloat = 60.0

    init(scene: SKScene? = nil) {
        self.scene = scene
    }

    // Helper: classify a touch as bottom-left or bottom-right control rectangles.
    // Control rectangles occupy the bottom 25% of the screen height (matching GameScene debug regions).
    private func isBottomLeft(_ pos: CGPoint, in scene: SKScene) -> Bool {
        let regionHeight = scene.size.height * 0.25
        return pos.x < scene.size.width * 0.5 && pos.y < regionHeight
    }
    private func isBottomRight(_ pos: CGPoint, in scene: SKScene) -> Bool {
        let regionHeight = scene.size.height * 0.25
        return pos.x >= scene.size.width * 0.5 && pos.y < regionHeight
    }

    // Forward touch events from the scene. Scene should call these from its touch handlers.
    func touchesBegan(_ touches: Set<UITouch>, in scene: SKScene) {
        self.scene = scene
        for t in touches {
            let pos = t.location(in: scene)
                if isBottomLeft(pos, in: scene) {
                // Bottom-left — movement joystick
                if leftTouch == nil {
                    leftTouch = t
                    // Anchor left joystick origin to the center of the left control rectangle so
                    // the knob stays centered when finger is up and behaves like a fixed virtual stick.
                    leftOrigin = CGPoint(x: scene.size.width * 0.25, y: scene.size.height * 0.25 * 0.5)
                    leftCurrent = pos
                }
            } else if isBottomRight(pos, in: scene) {
                // Bottom-right — aim / shoot (virtual stick anchored to right-area center)
                if rightTouch == nil {
                    rightTouch = t
                    rightRawPosition = pos
                    // Anchor origin to the center of the right control rectangle (bottom 25%).
                    rightOrigin = CGPoint(x: scene.size.width * 0.75, y: scene.size.height * 0.25 * 0.5)
                }
            } else {
                // Touches outside control areas are ignored (prevents accidental dragging)
            }
        }
    }

    func touchesMoved(_ touches: Set<UITouch>, in scene: SKScene) {
        for t in touches {
            if let lt = leftTouch, t == lt {
                leftCurrent = t.location(in: scene)
            } else if let rt = rightTouch, t == rt {
                rightRawPosition = t.location(in: scene)
            }
        }
    }

    func touchesEnded(_ touches: Set<UITouch>, in scene: SKScene) {
        for t in touches {
            if let lt = leftTouch, t == lt {
                leftTouch = nil
                leftCurrent = nil
            } else if let rt = rightTouch, t == rt {
                rightTouch = nil
                rightRawPosition = nil
                rightOrigin = nil
            }
        }
    }

    func touchesCancelled(_ touches: Set<UITouch>, in scene: SKScene) {
        // Treat cancelled as ended
        touchesEnded(touches, in: scene)
    }

    // InputController conformance
    func movementVector() -> CGVector {
        guard let current = leftCurrent else { return CGVector(dx: 0, dy: 0) }
        var dx = current.x - leftOrigin.x
        var dy = current.y - leftOrigin.y

        // Normalize by joystick radius to -1..1
        dx = max(-joystickRadius, min(joystickRadius, dx)) / joystickRadius
        dy = max(-joystickRadius, min(joystickRadius, dy)) / joystickRadius

        return CGVector(dx: dx, dy: dy)
    }

    // Aim point is computed relative to the player's position and constrained to a circle of radius `joystickRadius`.
    // This prevents dragging a crosshair anywhere on the screen and gives a fixed-radius aim control around the character.
    func aimPoint() -> CGPoint? {
        // Aim direction is taken from the vector (rightOrigin -> finger) and then applied
        // relative to the player's position. This makes the right-area behave like a virtual
        // stick anchored at the right-area center.
        guard let scene = scene, let rtPos = rightRawPosition, let origin = rightOrigin else { return nil }
        // Locate player node by name (GameScene sets player sprite name = "player")
        guard let playerNode = scene.childNode(withName: "player") else { return nil }
        let playerPos = playerNode.position

        // Vector from area center (origin) to raw finger position.
        // Copy this vector directly to the player's space so the player aims in the
        // same direction as the finger relative to the right-area center.
        let dx = rtPos.x - origin.x
        let dy = rtPos.y - origin.y

        // Direct-copy mapping: player looks toward (playerPos + (finger - areaCenter)).
        // This mirrors the "movement joystick" behavior where vector is taken relative to its origin.
        return CGPoint(x: playerPos.x + dx, y: playerPos.y + dy)
    }

    // For mobile we treat holding the right touch as continuous firing (Crimsonland-like feel)
    func isShooting() -> Bool {
        return rightTouch != nil
    }
}
#endif
