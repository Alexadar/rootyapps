import Foundation
import CoreGraphics

/// Shared game-wide definitions and small abstractions.
/// Keeps constants and protocols in a single place so other modules can import them.

struct PhysicsCategory {
    static let player: UInt32 = 1
    static let monster: UInt32 = 2
    static let bullet: UInt32 = 4
}

/// Input abstraction to prepare for adding mobile controls later.
/// Implementations will translate platform events (keyboard/mouse or touch/virtual sticks)
/// into movement/aim/shoot intents consumed by the game loop.
protocol InputController {
    /// Returns the current movement vector (-1..1 on each axis).
    func movementVector() -> CGVector

    /// Returns optional aim point in scene coordinates. If nil, aim may be derived from player-facing.
    func aimPoint() -> CGPoint?

    /// Returns true when a firing action should occur this frame (e.g. mouse down / touch tap / virtual button).
    func isShooting() -> Bool
}

// Provide default no-op platform event handlers so GameScene can forward events to the active input controller
// without needing to know the concrete input implementation type. Conforming types may override any of these.
#if os(macOS)
import AppKit
extension InputController {
    func keyDown(_ event: NSEvent) { }
    func keyUp(_ event: NSEvent) { }
    func mouseMoved(to location: CGPoint) { }
    func requestShoot() { }
}
#else
import UIKit
import SpriteKit
extension InputController {
    // Touch forwarding helpers (scene passed so inputs can convert coordinates)
    func touchesBegan(_ touches: Set<UITouch>, in scene: SKScene) { }
    func touchesMoved(_ touches: Set<UITouch>, in scene: SKScene) { }
    func touchesEnded(_ touches: Set<UITouch>, in scene: SKScene) { }
    func touchesCancelled(_ touches: Set<UITouch>, in scene: SKScene) { }
}
#endif
