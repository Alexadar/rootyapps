import Foundation

/// A hash over the exact bit patterns of simulation state, for cross-target determinism testing.
///
/// Pure, stateless. This is the *bit-level* half of the determinism contract. The other half is
/// physical — conserved E, L_z and the Carter constant — and both are required, because they catch
/// different failures:
///
///   * the hash catches "this machine produced different numbers than that machine", which is a
///     portability bug and is invisible to any physics assertion;
///   * conservation catches "the integrator is drifting", which is a correctness bug and is
///     invisible to the hash, because a drifting integrator drifts identically everywhere.
///
/// Hash a canonical set of trajectories, pin the digest as a golden, and run it on arm64 macOS, the
/// iOS Simulator and a device. Divergence fails CI. Same device as the gate-golden statistical tests
/// in ProducerTycoon.
///
/// FNV-1a over the raw IEEE-754 bit patterns: not cryptographic, and deliberately so — it must be
/// trivially reimplementable in a shader or another language if the GPU path ever needs auditing.
public struct DeterminismHash: Sendable, Equatable, CustomStringConvertible {
    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64       = 0x0000_0100_0000_01b3

    public private(set) var state: UInt64 = DeterminismHash.offsetBasis

    public init() {}

    /// Absorb one double by its bit pattern.
    ///
    /// NaN is canonicalised and -0.0 is folded to +0.0 before hashing. Both are values that compare
    /// equal (or unordered) yet carry distinguishable bits, so hashing them raw would report a
    /// divergence where the physics has none.
    public mutating func absorb(_ x: Double) {
        var bits: UInt64
        if x.isNaN {
            bits = 0x7ff8_0000_0000_0000
        } else if x == 0 {
            bits = 0
        } else {
            bits = x.bitPattern
        }
        for shift in stride(from: 0, to: 64, by: 8) {
            state ^= (bits >> UInt64(shift)) & 0xff
            state = state &* DeterminismHash.prime
        }
    }

    public mutating func absorb(_ xs: [Double]) {
        for x in xs { absorb(x) }
    }

    public mutating func absorb(_ n: Int64) {
        var bits = UInt64(bitPattern: n)
        for shift in stride(from: 0, to: 64, by: 8) {
            state ^= (bits >> UInt64(shift)) & 0xff
            state = state &* DeterminismHash.prime
        }
        bits = 0
    }

    public var digest: UInt64 { state }
    public var description: String { String(format: "%016llx", state) }

    /// One-shot digest of a state sequence.
    public static func of(_ values: [Double]) -> DeterminismHash {
        var h = DeterminismHash()
        h.absorb(values)
        return h
    }
}
