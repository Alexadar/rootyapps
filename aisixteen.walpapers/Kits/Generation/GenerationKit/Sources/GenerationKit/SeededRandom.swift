import Foundation

/// SplitMix64 — a small, fast, well-distributed generator with an exactly reproducible sequence.
///
/// Reproducibility is the whole point. A wallpaper stores its seed, so the same prompt and seed must
/// produce the same picture on any device, any launch, any Swift version. `SystemRandomNumberGenerator`
/// guarantees the opposite, and `Hasher` is salted per process, so neither can be used anywhere the
/// result is stored.
///
/// Reference: Steele, Lea & Flood, *Fast Splittable Pseudorandom Number Generators* (OOPSLA 2014);
/// this is the `splitmix64` variant published with xoshiro by Blackman & Vigna.
public struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        // A zero seed is legal for SplitMix64 (unlike xoshiro), but the golden-ratio nudge keeps
        // the first output of adjacent seeds well separated, which matters because our seeds are
        // often consecutive.
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    public init(seed: UInt32) { self.init(seed: UInt64(seed)) }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A stable 64-bit digest of a string.
///
/// `String.hashValue` cannot be used for anything that outlives the process — Swift salts it per
/// launch, so the same prompt would render a different picture every time the app started. This is
/// FNV-1a over UTF-8: unremarkable, but identical everywhere and forever.
public func stableHash(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01B3   // the FNV-1a 64-bit prime, 1099511628211
    }
    return hash
}

extension UInt32 {
    /// A fresh seed. Used when the user has not asked for a specific one.
    public static func randomSeed() -> UInt32 { UInt32.random(in: UInt32.min...UInt32.max) }
}
