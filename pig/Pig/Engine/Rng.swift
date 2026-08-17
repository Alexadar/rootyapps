import Foundation

/// Determinism, which replay and any future batched sweep both depend on.
///
/// **Counter-based and stateless.** A value is a pure function of `(seed, frame, stream, index)` —
/// there is no generator state anywhere, nothing to thread through the step, and nothing that can be
/// accidentally shared between worlds. Hashing the world index directly is what makes "one pig and
/// ten thousand pigs are the same code path" true rather than aspirational: world 0 draws the same
/// numbers whatever company it is computed in.
///
/// The standing rule: **the engine never calls `Double.random(in:)` or any system RNG.** One such
/// call makes a run unreproducible, and the failure is invisible until a replay diverges.
/// `VectorDisciplineTests` enforces it by scanning the source.
enum Rng {

    /// Distinct streams, so that changing how often one is drawn cannot shift another. A single
    /// shared counter would couple them: add one roll and every subsequent value changes, so a
    /// cosmetic edit silently alters the game.
    enum Stream: UInt64 {
        case dropAngle = 0x9E37
        case dropRadius = 0x85EB
        case dropSpread = 0xC2B2
        case dropLook = 0x27D4
        case dogAngle = 0x165667B1
        case dogTimer = 0x27D4EB2F
    }

    /// Vigna's SplitMix64, used as a mixing function rather than a generator: the input is the
    /// counter, not a mutable seed. Chosen over an ad-hoc hash because it has **published reference
    /// vectors**, which makes it the only genuinely third-party oracle in this engine.
    static func splitMix64(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniforms in `[0, 1)`.
    ///
    /// Element `i` of the flattened result is hashed on `i` itself, so for a fixed slot layout world
    /// `i` always draws the same numbers no matter how many worlds accompany it.
    static func uniform(_ shape: [Int], seed: UInt64, frame: Int, stream: Stream) -> Tensor {
        let count = shape.reduce(1, *)
        let base = splitMix64(seed &+ splitMix64(UInt64(bitPattern: Int64(frame)) &+ stream.rawValue))
        var out = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let h = splitMix64(base &+ (UInt64(i) &* 0x9E37_79B9_7F4A_7C15))
            // 53 significant bits, the most a Double carries exactly.
            out[i] = Double(h >> 11) * 0x1p-53
        }
        return Tensor(shape: shape, data: out)
    }

    /// Scale a `[0,1)` draw into a closed range without another hash.
    static func scaled(_ u: Tensor, into range: ClosedRange<Double>) -> Tensor {
        u * (range.upperBound - range.lowerBound) + range.lowerBound
    }
}
