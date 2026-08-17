import Foundation
import MLX

/// Determinism, which replay and batched sweep testing both depend on.
///
/// **Counter-based and stateless.** A value is a pure function of
/// `(seed, frame, stream, worldIndex, laneIndex)` — there is no generator state anywhere, nothing to
/// thread through the step, and nothing to accidentally share between worlds.
///
/// That last property is not a nicety, it is the whole reason this file is not one line of
/// `MLXRandom`. `MLXRandom.uniform(shape, key:)` produces a *different sequence for a different
/// output shape*, so world 0 draws different numbers in a batch of 1 than in a batch of 64. The
/// batch-invariance test caught exactly that: eight-hundred-step runs that agreed alone and diverged
/// in company. Hashing the world index directly makes "one world and ten thousand worlds are the
/// same code path" true rather than aspirational.
///
/// The standing rule: **never call `Double.random(in:)` or any system RNG.** One such call makes a
/// run unreproducible, and the failure is invisible until a replay diverges.
public enum Rng {

    /// Distinct streams, so that changing how often one is drawn cannot shift another.
    /// A single shared counter would couple them: add one spawn roll and every subsequent jitter
    /// value changes, so a cosmetic edit silently alters gameplay.
    public enum Stream: UInt64 {
        case laneSpawn = 0x9E37
        case targetSpeed = 0x85EB
        case targetOffset = 0xC2B2
        case targetKind = 0x27D4
    }

    // MARK: - Host-side mixing

    /// Vigna's SplitMix64, used as a mixing function rather than a generator: the input is the
    /// counter, not a mutable seed. Chosen over an ad-hoc hash because it has **published reference
    /// vectors**, which makes it the only genuinely third-party oracle in this engine — every other
    /// number here was picked by someone on this project.
    public static func splitMix64(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// One scalar per `(seed, frame, stream)`. Host-side, but once per frame rather than once per
    /// world — marshalling, not a loop over the batch.
    private static func base(seed: UInt64, frame: Int, stream: Stream) -> Int64 {
        let mixed = splitMix64(seed &+ splitMix64(UInt64(bitPattern: Int64(frame)) &+ stream.rawValue))
        return Int64(mixed % UInt64(modulus - 1)) + 1
    }

    // MARK: - Device-side expansion

    /// Lehmer / Park–Miller modulus (Park & Miller, CACM 1988), with a **quadratic** mixing step.
    ///
    /// The quadratic step is not decoration, and leaving it out was a real bug. A pure Lehmer chain
    /// is `h = (idx·A + base)·Aⁿ mod M` — **affine in the index**. Every lane therefore differs from
    /// lane 0 by a fixed constant, so the lanes are not independent: conditioning on one determines
    /// the rest.
    ///
    /// That is exactly how it failed. The flock spawns only on frames where lane 4 rolls below 0.02,
    /// and on that conditioned subset lanes 5, 6 and 7 were nearly constant — eight consecutive
    /// spawns arrived at `dy` of −2.08, +2.81, +2.81, +2.88, +2.85, +2.76, +2.89, +2.77, all facing
    /// the same way. Structure invisible in any single lane, fatal the moment two are used together.
    ///
    /// `h·h` peaks near `(2³¹)² ≈ 4.6·10¹⁸`, comfortably inside Int64's `9.2·10¹⁸`, so this still
    /// needs no bitwise operations — which MLX's integer support does not uniformly provide.
    private static let modulus: Int64 = 2_147_483_647          // 2³¹ − 1, prime
    private static let multiplier: Int64 = 48_271
    private static let multiplier2: Int64 = 16_807             // Park–Miller's original
    private static let addend1: Int64 = 1_013_904_223
    private static let addend2: Int64 = 1_664_525

    /// Break the affinity. Two quadratic rounds separated by distinct multipliers.
    private static func mix(_ start: MLXArray) -> MLXArray {
        var h = start % modulus
        h = (h * h + addend1) % modulus
        h = (h * multiplier) % modulus
        h = (h * h + addend2) % modulus
        h = (h * multiplier2) % modulus
        return h
    }

    /// Cached index ramps. `arange` is a constant for a given length, but rebuilding it every frame
    /// costs an operation every frame — and this engine is bound by operation *count*, not by
    /// arithmetic, so constants are worth hoisting.
    private static var ramps: [Int: MLXArray] = [:]
    private static func ramp(_ n: Int) -> MLXArray {
        if let r = ramps[n] { return r }
        let r = MLXArray.arange(n, dtype: .int64)
        ramps[n] = r
        return r
    }

    /// Uniforms in `[0, 1)`, shape `[B, lanes]`.
    ///
    /// **Draw every stream a frame needs in one call.** Each hash is about a dozen operations, and
    /// the step is bound by how many operations it issues; four separate draws cost four times as
    /// much as one draw of four lanes, for identical numbers. `lanes` is fixed by the layout, so
    /// element `[i, j]` still hashes on the flat index `i·lanes + j` and world `i` is unaffected by
    /// how many worlds accompany it.
    public static func uniforms(batch B: Int, lanes: Int, seed: UInt64, frame: Int) -> MLXArray {
        let count = B * lanes
        let h = mix(ramp(count) * multiplier + base(seed: seed, frame: frame, stream: .laneSpawn))
        return (h.asType(.float32) / Float(modulus)).reshaped([B, lanes])
    }

    /// Uniforms in `[0, 1)`.
    ///
    /// **The leading axis is the world axis.** Element `[i, j…]` is hashed on the flat index
    /// `i·L + j`, where `L` is the product of the trailing dimensions — so for a fixed slot layout,
    /// world `i` always draws the same numbers no matter how many worlds it is computed alongside.
    public static func uniform(_ shape: [Int], seed: UInt64, frame: Int, stream: Stream) -> MLXArray {
        let count = shape.reduce(1, *)
        let h = mix(ramp(count) * multiplier + base(seed: seed, frame: frame, stream: stream))
        return (h.asType(.float32) / Float(modulus)).reshaped(shape)
    }

    /// Uniforms scaled into a closed range, computed on device.
    public static func uniform(_ shape: [Int], in range: ClosedRange<Double>,
                               seed: UInt64, frame: Int, stream: Stream) -> MLXArray {
        let u = uniform(shape, seed: seed, frame: frame, stream: stream)
        return MLXArray(Float(range.lowerBound))
            + u * MLXArray(Float(range.upperBound - range.lowerBound))
    }

    /// Scale a `[0,1)` draw into a range without another hash.
    public static func scaled(_ u: MLXArray, into range: ClosedRange<Double>) -> MLXArray {
        MLXArray(Float(range.lowerBound)) + u * MLXArray(Float(range.upperBound - range.lowerBound))
    }
}
