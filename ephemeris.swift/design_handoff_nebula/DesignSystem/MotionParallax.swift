import SwiftUI

#if os(iOS)
import CoreMotion

/// Publishes a small, smoothed parallax offset from the device's tilt (the gravity
/// vector), so the deep-space backdrop drifts as you angle the phone — a subtle sense
/// of looking *into* the sky. Inert (zero) when device motion isn't available.
@MainActor
final class MotionParallax: ObservableObject {
    /// One shared source so the backdrop's tilt persists across tab switches
    /// (a fresh per-tab instance would snap back to zero and visibly jump).
    static let shared = MotionParallax()

    /// Roughly [-1, 1] on each axis; **0 at launch**, then responds to how much you
    /// tilt *away* from that resting hold (so holding the phone upright isn't already
    /// pinned to a corner).
    @Published var tilt: CGSize = .zero

    private let manager = CMMotionManager()
    private var smoothed: CGSize = .zero
    private var base: (x: Double, y: Double)?      // gravity captured on the first sample

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            if self.base == nil { self.base = (g.x, g.y) }   // zero-point = however it's held now
            let gain = 2.2                                    // ~25° of tilt → full deflection
            func clamp(_ v: Double) -> Double { max(-1, min(1, v)) }
            let target = CGSize(width:  clamp((g.x - self.base!.x) * gain),
                                height: clamp(-(g.y - self.base!.y) * gain))
            let a = 0.12                                       // low-pass: glide, don't jitter
            self.smoothed.width  += (target.width  - self.smoothed.width)  * a
            self.smoothed.height += (target.height - self.smoothed.height) * a
            self.tilt = self.smoothed
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        smoothed = .zero
        base = nil
        tilt = .zero
    }
}
#else

/// No-op on platforms without device motion (macOS) — the backdrop stays put.
@MainActor
final class MotionParallax: ObservableObject {
    static let shared = MotionParallax()
    @Published var tilt: CGSize = .zero
    func start() {}
    func stop() {}
}
#endif
