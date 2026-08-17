import Foundation

/// Sebastiano Vigna's SplitMix64, reimplemented here rather than reached for.
///
/// The generator is chosen for one reason: it is **published with reference vectors**, which makes
/// it the only thing in this Kit with a genuine external authority to test against. That matters
/// more than it sounds. Determinism is the hinge of the whole design — the batched GPU sim and this
/// scalar reference must build byte-identical geometry from a seed before comparing their answers
/// means anything, and a future Python torchsim has to reproduce the same districts on a different
/// machine in a different language.
///
/// Two rules follow, and both are tested:
///
/// * `Double.random(in:using:)` and `Int.random(in:using:)` are **never** called. Their mapping from
///   bits to values is implementation-defined and may change between Swift versions, which would
///   silently regenerate every district. The conversions below are written out instead.
/// * Nothing in generation may depend on `Set` or `Dictionary` iteration order.
///
/// Reference: http://prng.di.unimi.it/splitmix64.c
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

    /// A double in [0, 1), built from an explicit 53-bit mantissa — the same construction the
    /// reference implementations use, and trivially reproducible in any other language.
    public mutating func unitDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)   // 2^-53
    }

    public mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unitDouble() * (range.upperBound - range.lowerBound)
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

    /// A tensor of independent uniforms in [0, 1).
    ///
    /// A counter-based generator is sequential by construction — that is what makes it reproducible —
    /// so this is the one place a per-element loop is unavoidable. Drawing a whole tensor at once
    /// keeps it here, in the primitive, instead of leaking a loop into the level generator.
    public mutating func uniforms(_ count: Int) -> Tensor {
        var out = [Double](repeating: 0, count: count)
        for i in 0..<count { out[i] = unitDouble() }
        return Tensor(shape: [count], data: out)
    }

    /// Fisher–Yates, driven by `int(in:)` so the shuffle is as reproducible as everything else.
    public mutating func shuffled<T>(_ items: [T]) -> [T] {
        var a = items
        guard a.count > 1 else { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            let j = int(in: 0...i)
            a.swapAt(i, j)
        }
        return a
    }
}

/// Smooth 2-D value noise on an integer lattice, seeded from the same PRNG.
///
/// Rooftop heights come from this rather than from independent uniform draws, and the reason is
/// physics rather than aesthetics. At a fixed launch elevation the greatest *rise* the frog can
/// reach at any power is `v²/(4g)` — so a neighbour more than that much taller is unreachable no
/// matter what the player does. Independent heights over a range wider than that would make most
/// generated districts unsolvable by construction, and the generator would spend its entire budget
/// rejecting them. A smooth field keeps neighbours climbable and makes the occasional deliberate
/// spike meaningful: that spike is a fly-gated shortcut. The physics writes the level design.
public struct HeightField: Sendable {
    private let gradients: [Double]
    private let size: Int

    public init(seed: UInt64, size: Int = 16) {
        var rng = SplitMix64(seed: seed &* 0x2545F4914F6CDD1D &+ 0x9E3779B9)
        self.size = size
        self.gradients = (0..<(size * size)).map { _ in rng.unitDouble() }
    }

    private func lattice(_ x: Int, _ z: Int) -> Double {
        let xi = ((x % size) + size) % size
        let zi = ((z % size) + size) % size
        return gradients[zi * size + xi]
    }

    /// Smoothstep-interpolated values at a whole grid of lattice coordinates at once.
    public func values(x: Tensor, z: Tensor) -> Tensor {
        precondition(x.count == z.count)
        var out = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count { out[i] = value(x: x[i], z: z[i]) }
        return Tensor(shape: x.shape, data: out)
    }

    /// Smoothstep-interpolated value in [0, 1] at continuous lattice coordinates.
    public func value(x: Double, z: Double) -> Double {
        let x0 = Int(floor(x)), z0 = Int(floor(z))
        let fx = x - Double(x0), fz = z - Double(z0)
        let sx = fx * fx * (3 - 2 * fx)
        let sz = fz * fz * (3 - 2 * fz)

        let v00 = lattice(x0, z0), v10 = lattice(x0 + 1, z0)
        let v01 = lattice(x0, z0 + 1), v11 = lattice(x0 + 1, z0 + 1)

        let top = v00 + (v10 - v00) * sx
        let bottom = v01 + (v11 - v01) * sx
        return top + (bottom - top) * sz
    }
}
