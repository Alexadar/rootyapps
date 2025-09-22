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
