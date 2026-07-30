import Foundation

/// Reel demo animation, gated on the `TRUECOURSE_DEMO` env hook (no effect in the shipping app).
///
/// Each scene opens, scrolls/taps during a short **warm-up hold**, and only then do the values
/// start moving — and they move slowly enough to read, because the reel now plays at natural
/// speed (the tour is kept under `preview_maxlen`, so `make_reel.sh` applies no speed-up).
enum DemoSweep {
    static var isOn: Bool { LaunchOverride.isSet("TRUECOURSE_DEMO") }

    static let tickInterval: TimeInterval = 0.06
    static let warmup = 25        // ~1.5 s still, while the scene settles
    // ~4.2 s per from→to. The preview is speed-fit (~1.5×), so this reads as ~2.8 s on screen.
    static let ticksPerLeg = 70

    /// Which leg we're on and how far through it (eased). `nil` while warming up.
    static func phase(tick: Int, legs: Int,
                      warmup: Int = warmup, ticksPerLeg: Int = ticksPerLeg) -> (leg: Int, ease: Double)? {
        guard tick > warmup, legs > 0 else { return nil }
        let n = tick - warmup
        let leg = (n / ticksPerLeg) % legs
        let t = min(Double(n % ticksPerLeg) / Double(ticksPerLeg - 8), 1)
        return (leg, t * t * (3 - 2 * t))   // smoothstep
    }

    /// Ping-pong between two values, eased. `nil` while warming up.
    static func value(tick: Int, a: Double, b: Double,
                      warmup: Int = warmup, ticksPerLeg: Int = ticksPerLeg) -> Double? {
        guard let p = phase(tick: tick, legs: 2, warmup: warmup, ticksPerLeg: ticksPerLeg) else { return nil }
        let from = p.leg == 0 ? a : b
        let to   = p.leg == 0 ? b : a
        return (from + (to - from) * p.ease).rounded()
    }
}
