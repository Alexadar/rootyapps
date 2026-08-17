import Foundation

/// Sebastiano Vigna's SplitMix64, reimplemented here rather than reached for.
///
/// Chosen for one reason: it is **published with reference vectors**, which makes it the only
/// thing in this Kit with a genuine external authority to test against. A `Reading` must be
/// replayable exactly from its seed — forever, on any device, under any Swift version — so:
///
/// * `Double.random(in:using:)` / `Int.random(in:using:)` are **never** called. Their mapping
///   from bits to values is implementation-defined and may change between Swift versions, which
///   would silently re-deal every saved reading. The conversions below are written out instead.
/// * Nothing may depend on `Set` or `Dictionary` iteration order.
///
/// Reference: http://prng.di.unimi.it/splitmix64.c
/// (Same implementation as froggo2's ReachabilityKit — kept as an independent copy because Kits
/// are standalone packages; the reference-vector test pins both to the same published truth.)
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { self.state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// A double in [0, 1), built from an explicit 53-bit mantissa.
    public mutating func unitDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)   // 2^-53
    }

    /// A uniform integer in `range`, debiased by Lemire's multiply-shift rejection method.
    public mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound) &+ 1
        guard span > 1 else { return range.lowerBound }

        var m = next().multipliedFullWidth(by: span)
        if m.low < span {
            let threshold = (0 &- span) % span
            while m.low < threshold {
                m = next().multipliedFullWidth(by: span)
            }
        }
        return range.lowerBound + Int(m.high)
    }

    /// True with probability `p`.
    public mutating func chance(_ p: Double) -> Bool { unitDouble() < p }
}
