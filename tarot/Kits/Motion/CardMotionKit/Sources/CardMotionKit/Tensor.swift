import Foundation

/// The in-house vector layer. Foundation only — no Accelerate, no simd, no MLX.
///
/// Lifted from froggo2's `ReachabilityKit/Tensor.swift` (the same precedent bigpinkcat's
/// TensorKit followed), trimmed to the shapes card motion needs and extended with the kernels
/// it lacks. The rule it exists to enforce is unchanged:
///
///   **No domain code contains a loop over worlds or over cards.**
///
/// Loops live *here*, inside the elementwise kernels, and nowhere else. A single card moving
/// under a finger and four thousand emulated draws run the *same* code; the leading dimension
/// is the only difference.
///
/// Shapes used by the kernel:
///
///   `[N]`     — one value per world (pointer, press, light angle)
///   `[N, C]`  — one value per card lane, C = card capacity (78 in the game)
///
/// Absent or inactive cards are *carried*, never removed — masked, not skipped. Ragged arrays
/// mean loops.
///
/// `Double` throughout. The golden-trajectory tests hash raw bit patterns, and `Float` drift
/// between build configurations would flip them.
public struct Tensor: Sendable, Equatable {
    public let shape: [Int]
    public var data: [Double]

    public init(shape: [Int], data: [Double]) {
        precondition(shape.reduce(1, *) == data.count,
                     "shape \(shape) does not describe \(data.count) elements")
        self.shape = shape
        self.data = data
    }

    public init(repeating value: Double, shape: [Int]) {
        self.init(shape: shape, data: [Double](repeating: value, count: shape.reduce(1, *)))
    }

    public static func zeros(_ shape: [Int]) -> Tensor { Tensor(repeating: 0, shape: shape) }
    public static func ones(_ shape: [Int]) -> Tensor { Tensor(repeating: 1, shape: shape) }

    public var count: Int { data.count }
    public subscript(i: Int) -> Double { data[i] }
}

// MARK: - Elementwise arithmetic

extension Tensor {
    @inline(__always)
    static func zip(_ a: Tensor, _ b: Tensor, _ op: (Double, Double) -> Double) -> Tensor {
        precondition(a.count == b.count, "shape mismatch: \(a.shape) vs \(b.shape)")
        var out = a.data
        for i in 0..<out.count { out[i] = op(a.data[i], b.data[i]) }
        return Tensor(shape: a.shape, data: out)
    }

    @inline(__always)
    func map(_ op: (Double) -> Double) -> Tensor {
        var out = data
        for i in 0..<out.count { out[i] = op(out[i]) }
        return Tensor(shape: shape, data: out)
    }

    public static func + (a: Tensor, b: Tensor) -> Tensor { zip(a, b, +) }
    public static func - (a: Tensor, b: Tensor) -> Tensor { zip(a, b, -) }
    public static func * (a: Tensor, b: Tensor) -> Tensor { zip(a, b, *) }
    public static func / (a: Tensor, b: Tensor) -> Tensor { zip(a, b, /) }

    public static func + (a: Tensor, s: Double) -> Tensor { a.map { $0 + s } }
    public static func - (a: Tensor, s: Double) -> Tensor { a.map { $0 - s } }
    public static func * (a: Tensor, s: Double) -> Tensor { a.map { $0 * s } }
    public static func / (a: Tensor, s: Double) -> Tensor { a.map { $0 / s } }
    public static func + (s: Double, a: Tensor) -> Tensor { a.map { s + $0 } }
    public static func - (s: Double, a: Tensor) -> Tensor { a.map { s - $0 } }
    public static func * (s: Double, a: Tensor) -> Tensor { a.map { s * $0 } }
    public static prefix func - (a: Tensor) -> Tensor { a.map { -$0 } }

    public var squareRoot: Tensor { map { $0 < 0 ? .nan : $0.squareRoot() } }
    public var absolute: Tensor { map { Swift.abs($0) } }
    public var isFiniteMask: Tensor { map { $0.isFinite ? 1 : 0 } }

    /// Elementwise sine. Foundation `sin` is acceptable here: golden hashes are scoped to one
    /// platform (the Kit's own macOS test run), unlike bigpinkcat's cross-device goldens which
    /// needed hand-rolled transcendentals.
    public var sine: Tensor { map { Foundation.sin($0) } }

    /// x³ — the juice envelope's cubic decay (and its square, via multiply, the quadratic one).
    public var cubed: Tensor { map { $0 * $0 * $0 } }

    public func clamped(min lo: Double, max hi: Double) -> Tensor {
        map { Swift.min(Swift.max($0, lo), hi) }
    }

    public static func minimum(_ a: Tensor, _ b: Tensor) -> Tensor { zip(a, b, Swift.min) }
    public static func maximum(_ a: Tensor, _ b: Tensor) -> Tensor { zip(a, b, Swift.max) }
    public func minimum(_ s: Double) -> Tensor { map { Swift.min($0, s) } }
    public func maximum(_ s: Double) -> Tensor { map { Swift.max($0, s) } }
}

// MARK: - Masks
//
// A mask is a Tensor of 0.0 / 1.0. Keeping masks as numbers rather than Bools is what makes the
// whole program branchless: a conditional becomes a multiply, and "if this card is in the deck,
// skip it" becomes "multiply its contribution by zero".

extension Tensor {
    public static func .< (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { $0 < $1 ? 1 : 0 } }
    public static func .<= (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { $0 <= $1 ? 1 : 0 } }
    public static func .> (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { $0 > $1 ? 1 : 0 } }
    public static func .>= (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { $0 >= $1 ? 1 : 0 } }

    public static func .< (a: Tensor, s: Double) -> Tensor { a.map { $0 < s ? 1 : 0 } }
    public static func .<= (a: Tensor, s: Double) -> Tensor { a.map { $0 <= s ? 1 : 0 } }
    public static func .> (a: Tensor, s: Double) -> Tensor { a.map { $0 > s ? 1 : 0 } }
    public static func .>= (a: Tensor, s: Double) -> Tensor { a.map { $0 >= s ? 1 : 0 } }

    /// Code equality for phase lanes: codes are small integers stored as Doubles, so equality
    /// is "within half a step" — exact for every value the kernel writes.
    public static func .== (a: Tensor, s: Double) -> Tensor { a.map { Swift.abs($0 - s) < 0.5 ? 1 : 0 } }

    public static func .&& (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { ($0 > 0.5 && $1 > 0.5) ? 1 : 0 } }
    public static func .|| (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { ($0 > 0.5 || $1 > 0.5) ? 1 : 0 } }
    public var not: Tensor { map { $0 > 0.5 ? 0 : 1 } }

    /// Edge detection by arithmetic: 1 where `now` is set and `previous` was not.
    /// The vector form of `if justHappened` — semantic events (grabbed, landed, flip apex)
    /// are all built from this, never from animation frames.
    public static func newlySet(now: Tensor, previous: Tensor) -> Tensor {
        now * previous.not
    }

    /// The branchless conditional. `mask ? a : b`, elementwise.
    public static func which(_ mask: Tensor, _ a: Tensor, _ b: Tensor) -> Tensor {
        precondition(mask.count == a.count && a.count == b.count)
        var out = a.data
        for i in 0..<out.count { out[i] = mask.data[i] > 0.5 ? a.data[i] : b.data[i] }
        return Tensor(shape: a.shape, data: out)
    }

    public static func which(_ mask: Tensor, _ a: Tensor, _ b: Double) -> Tensor {
        which(mask, a, Tensor(repeating: b, shape: a.shape))
    }

    public static func which(_ mask: Tensor, _ a: Double, _ b: Tensor) -> Tensor {
        which(mask, Tensor(repeating: a, shape: b.shape), b)
    }
}

infix operator .< : ComparisonPrecedence
infix operator .<= : ComparisonPrecedence
infix operator .> : ComparisonPrecedence
infix operator .>= : ComparisonPrecedence
infix operator .== : ComparisonPrecedence
infix operator .&& : LogicalConjunctionPrecedence
infix operator .|| : LogicalDisjunctionPrecedence

// MARK: - Broadcast

extension Tensor {
    /// `[N]` → `[N, C]`, repeating each world's value across its card lanes — how a per-world
    /// pointer meets per-card state.
    public func expandedPerLane(_ c: Int) -> Tensor {
        precondition(shape.count == 1)
        let n = shape[0]
        var out = [Double](repeating: 0, count: n * c)
        for w in 0..<n {
            let v = data[w]
            for i in 0..<c { out[w * c + i] = v }
        }
        return Tensor(shape: [n, c], data: out)
    }
}

// MARK: - Structural primitives

extension Tensor {
    /// Among lanes where `mask` is set, a one-hot at the lane with the smallest value —
    /// all-zero for a world whose mask is empty. Ties break to the lowest lane index,
    /// deterministically. This is "grab the topmost card of the deck" as a scatter.
    public static func oneHotOfMaskedMin(values: Tensor, mask: Tensor) -> Tensor {
        precondition(values.shape.count == 2 && values.shape == mask.shape)
        let n = values.shape[0], c = values.shape[1]
        var out = [Double](repeating: 0, count: n * c)
        for w in 0..<n {
            var best = Double.infinity
            var bestLane = -1
            let base = w * c
            for i in 0..<c where mask.data[base + i] > 0.5 && values.data[base + i] < best {
                best = values.data[base + i]
                bestLane = i
            }
            if bestLane >= 0 { out[base + bestLane] = 1 }
        }
        return Tensor(shape: [n, c], data: out)
    }

    /// The flat lane indices where a mask is set, for one world. The only place the vector
    /// world converts back into a list, and it exists purely so results can be reported.
    public func setLanes(world: Int) -> [Int] {
        precondition(shape.count == 2)
        let c = shape[1]
        return (0..<c).filter { data[world * c + $0] > 0.5 }
    }

    /// One world's value of an `[N]` tensor, for reporting.
    public func scalar(world: Int) -> Double {
        precondition(shape.count == 1)
        return data[world]
    }
}

// MARK: - Reductions

extension Tensor {
    /// Sum over the last axis. `[N, C]` → `[N]`.
    public func sumLast() -> Tensor {
        let last = shape[shape.count - 1]
        let outer = count / last
        var out = [Double](repeating: 0, count: outer)
        for o in 0..<outer {
            var acc = 0.0
            let base = o * last
            for i in 0..<last { acc += data[base + i] }
            out[o] = acc
        }
        return Tensor(shape: Array(shape.dropLast()), data: out)
    }

    /// Maximum over the last axis.
    public func maxLast() -> Tensor {
        let last = shape[shape.count - 1]
        let outer = count / last
        var out = [Double](repeating: -.infinity, count: outer)
        for o in 0..<outer {
            var acc = -Double.infinity
            let base = o * last
            for i in 0..<last { acc = Swift.max(acc, data[base + i]) }
            out[o] = acc
        }
        return Tensor(shape: Array(shape.dropLast()), data: out)
    }

    /// Minimum over the last axis.
    public func minLast() -> Tensor {
        let last = shape[shape.count - 1]
        let outer = count / last
        var out = [Double](repeating: .infinity, count: outer)
        for o in 0..<outer {
            var acc = Double.infinity
            let base = o * last
            for i in 0..<last { acc = Swift.min(acc, data[base + i]) }
            out[o] = acc
        }
        return Tensor(shape: Array(shape.dropLast()), data: out)
    }

    /// "Is anything set" over the last axis — the vector form of `contains(where:)`.
    public func anyLast() -> Tensor { (sumLast() .> 0.5) }
}
