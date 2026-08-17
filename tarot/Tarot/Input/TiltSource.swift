import Foundation

#if os(iOS)
import CoreMotion

/// Device-gravity light source for the foil (ephemeris's MotionParallax pattern: gravity, not
/// attitude; first sample is the zero point so holding the phone naturally isn't already
/// pinned to a corner; low-passed so it glides).
///
/// The kernel does its own smoothing too (`lightRate`) — this layer only normalizes and
/// zero-references; keeping BOTH is deliberate: this one absorbs sensor noise, the kernel one
/// makes the value deterministic under test.
@MainActor
final class TiltSource {
    static let shared = TiltSource()

    private let manager = CMMotionManager()
    private var zero: (x: Double, y: Double)?
    private(set) var lightX: Double = 0
    private(set) var lightZ: Double = 0
    private let gain = 2.2

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            if zero == nil { zero = (g.x, g.y) }
            let dx = (g.x - (zero?.x ?? 0)) * gain
            let dy = (g.y - (zero?.y ?? 0)) * gain
            lightX = min(max(dx, -1), 1)
            lightZ = min(max(-dy, -1), 1)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        zero = nil
    }

    /// Cursor hover fallback for pointer-driven cases (iPad trackpad).
    func setPointerLight(x: Double, z: Double) {
        if !manager.isDeviceMotionActive {
            lightX = x
            lightZ = z
        }
    }
}

#else

/// macOS: no CMMotionManager exists in the SDK (verified) — the light angle is the cursor.
/// Identical API surface so call sites need no conditionals (the MotionParallax pattern).
@MainActor
final class TiltSource {
    static let shared = TiltSource()
    private(set) var lightX: Double = 0
    private(set) var lightZ: Double = 0

    func start() {}
    func stop() {}

    func setPointerLight(x: Double, z: Double) {
        lightX = min(max(x, -1), 1)
        lightZ = min(max(z, -1), 1)
    }
}

#endif
