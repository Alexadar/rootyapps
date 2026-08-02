import Foundation

/// Seedable deterministic RNG for the game engine (SplitMix64 core).
/// Mirrors the torchsim/TS helpers: `randInt` is inclusive on both ends,
/// `uniform` is half-open [lo, hi).
public struct GameRandom {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed &+ 0x9E3779B97F4A7C15
    }

    private mutating func nextUInt64() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    public mutating func next() -> Double {
        Double(nextUInt64() >> 11) * (1.0 / 9007199254740992.0)
    }

    /// TS randInt(lo, hi): inclusive both ends. floor(u*(hi-lo+1))+lo.
    public mutating func randInt(_ lo: Double, _ hi: Double) -> Double {
        (Foundation.floor(next() * (hi - lo + 1)) + lo)
    }

    public mutating func randInt(_ lo: Int, _ hi: Int) -> Int {
        Int(randInt(Double(lo), Double(hi)))
    }

    public mutating func uniform(_ lo: Double, _ hi: Double) -> Double {
        lo + next() * (hi - lo)
    }

    public mutating func chance(_ p: Double) -> Bool {
        next() < p
    }

    /// Standard normal via Box-Muller.
    public mutating func gaussian() -> Double {
        var u1 = next()
        if u1 <= 0 { u1 = .leastNonzeroMagnitude }
        let u2 = next()
        return (-2 * Foundation.log(u1)).squareRoot() * Foundation.cos(2 * Double.pi * u2)
    }

    /// Index sampled proportionally to non-negative weights (sum must be > 0).
    public mutating func weightedIndex(_ weights: [Double]) -> Int {
        let total = weights.reduce(0, +)
        var r = next() * total
        for (i, w) in weights.enumerated() {
            r -= w
            if r < 0 { return i }
        }
        return weights.count - 1
    }
}

@inlinable
public func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
    min(max(v, lo), hi)
}

/// TS Math.round semantics: half rounds UP (towards +inf), so tsRound(-1.5)
/// == -1 while Swift's .rounded() gives -2. The TS game is the parity target.
@inlinable
public func tsRound(_ x: Double) -> Double {
    (x + 0.5).rounded(.down)
}
