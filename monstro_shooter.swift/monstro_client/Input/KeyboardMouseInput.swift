import Foundation
import CoreGraphics
#if os(macOS)
import AppKit

/// macOS keyboard + mouse input controller.
/// GameScene forwards NSEvent callbacks to this object which implements InputController.
/// Designed so we can later add a touch-based implementation for mobile platforms.
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
