import Foundation

/// Counter-based randomness: a stateless hash of `(seed, tick, stream, world, lane)`.
///
/// The kernel never carries RNG state, because sequential state is what breaks batch
/// invariance — citypigeon measured exactly this failure with `MLXRandom`, whose sequences
/// depend on the draw *shape*, so world 0 alone and world 0 in a batch saw different numbers.
/// A counter-based hash gives every (world, lane) its own reproducible value regardless of
/// how many neighbours are computed alongside it.
///
/// The mix is SplitMix64's finalizer applied to the combined key. Not cryptographic; it only
/// has to be uniform enough for phase offsets and cosmetic jitter, and trivially reproducible.
public enum LaneNoise {

    @inline(__always)
    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    @inline(__always)
    static func combined(seed: UInt64, tick: UInt64, stream: UInt64,
                         world: UInt64, lane: UInt64) -> UInt64 {
        // Each component passes through the mixer before combining, so adjacent worlds/lanes
        // land far apart. The chain is order-sensitive on purpose.
        mix(mix(mix(mix(mix(seed) ^ tick) ^ stream) ^ world) ^ lane)
    }

    /// A uniform in [0, 1) per (world, lane) — `[N, C]`.
    public static func uniforms(seed: UInt64, tick: UInt64, stream: UInt64,
                                worlds n: Int, lanes c: Int) -> Tensor {
        var out = [Double](repeating: 0, count: n * c)
        for w in 0..<n {
            for i in 0..<c {
                let bits = combined(seed: seed, tick: tick, stream: stream,
                                    world: UInt64(w), lane: UInt64(i))
                out[w * c + i] = Double(bits >> 11) * (1.0 / 9_007_199_254_740_992.0)   // 2^-53
            }
        }
        return Tensor(shape: [n, c], data: out)
    }
}
