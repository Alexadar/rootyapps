import Foundation

/// The in-house vector layer. Foundation only — no Accelerate, no simd, no MLX.
///
/// Every piece of game mathematics in this Kit is written against this type, and the rule it exists
/// to enforce is:
///
///   **No domain code contains a loop over worlds, over rooftops, or over pairs of rooftops.**
///
/// Loops live *here*, inside the elementwise kernels, and nowhere else. That is the same discipline
/// `monstro_shooter.swift/torchsim/env_torch.py` follows — its `_core()` has no loop over entities,
/// only tensor algebra — and it is what makes batching free rather than a rewrite. A district
/// solved on its own and ten thousand districts solved together run the *same* code; the leading
/// dimension is the only difference.
///
/// Shapes used by the game:
///
///   `[N]`      — one value per world
///   `[N, K]`   — one value per rooftop, K = rooftop slot capacity
///   `[N, K, K]` — one value per ordered pair of rooftops (the adjacency cube)
///
/// Absent rooftops are *carried*, never removed: a district with fewer than K roofs keeps the empty
/// slots and masks them out. Removing them would mean ragged arrays, and ragged arrays mean loops.
///
/// `Double` throughout. Reachability is a boolean, and near the envelope boundary a Float rounding
/// difference does not shift an answer slightly — it flips it.
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

    public func reshaped(_ newShape: [Int]) -> Tensor {
        Tensor(shape: newShape, data: data)
    }
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
    public static func / (s: Double, a: Tensor) -> Tensor { a.map { s / $0 } }
    public static prefix func - (a: Tensor) -> Tensor { a.map { -$0 } }

    public var squareRoot: Tensor { map { $0 < 0 ? .nan : $0.squareRoot() } }
    public var absolute: Tensor { map { Swift.abs($0) } }
    public var isFiniteMask: Tensor { map { $0.isFinite ? 1 : 0 } }

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
// whole program branchless: a conditional becomes a multiply, and "if this roof is absent, skip it"
// becomes "multiply its contribution by zero" — which costs the same whether it is taken or not,
// and vectorises without a thought.

extension Tensor {
    public static func .< (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { $0 < $1 ? 1 : 0 } }
    public static func .<= (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { $0 <= $1 ? 1 : 0 } }
    public static func .> (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { $0 > $1 ? 1 : 0 } }
    public static func .>= (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { $0 >= $1 ? 1 : 0 } }

    public static func .< (a: Tensor, s: Double) -> Tensor { a.map { $0 < s ? 1 : 0 } }
    public static func .<= (a: Tensor, s: Double) -> Tensor { a.map { $0 <= s ? 1 : 0 } }
    public static func .> (a: Tensor, s: Double) -> Tensor { a.map { $0 > s ? 1 : 0 } }
    public static func .>= (a: Tensor, s: Double) -> Tensor { a.map { $0 >= s ? 1 : 0 } }

    public static func .&& (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { ($0 > 0.5 && $1 > 0.5) ? 1 : 0 } }
    public static func .|| (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { ($0 > 0.5 || $1 > 0.5) ? 1 : 0 } }
    public var not: Tensor { map { $0 > 0.5 ? 0 : 1 } }

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
infix operator .&& : LogicalConjunctionPrecedence
infix operator .|| : LogicalDisjunctionPrecedence

// MARK: - Pairwise expansion
//
// The move that replaces the double loop `for a in roofs { for b in roofs { ... } }`. Given
// per-roof values `[N, K]`, `rows` repeats each roof down a column and `cols` repeats it across a
// row; an operation between the two touches every ordered pair at once.

extension Tensor {
    /// `[N, K]` → `[N, K, K]` with `out[n, i, j] = self[n, i]` — the *source* of each pair.
    public func expandedAsRows() -> Tensor {
        precondition(shape.count == 2)
        let n = shape[0], k = shape[1]
        var out = [Double](repeating: 0, count: n * k * k)
        for w in 0..<n {
            for i in 0..<k {
                let v = data[w * k + i]
                let base = w * k * k + i * k
                for j in 0..<k { out[base + j] = v }
            }
        }
        return Tensor(shape: [n, k, k], data: out)
    }

    /// `[N, K]` → `[N, K, K]` with `out[n, i, j] = self[n, j]` — the *target* of each pair.
    public func expandedAsColumns() -> Tensor {
        precondition(shape.count == 2)
        let n = shape[0], k = shape[1]
        var out = [Double](repeating: 0, count: n * k * k)
        for w in 0..<n {
            for i in 0..<k {
                let base = w * k * k + i * k
                for j in 0..<k { out[base + j] = data[w * k + j] }
            }
        }
        return Tensor(shape: [n, k, k], data: out)
    }

    /// `[N]` → `[N, K]`, repeating each world's value across its rooftops.
    public func expandedPerRoof(_ k: Int) -> Tensor {
        precondition(shape.count == 1)
        let n = shape[0]
        var out = [Double](repeating: 0, count: n * k)
        for w in 0..<n {
            let v = data[w]
            for i in 0..<k { out[w * k + i] = v }
        }
        return Tensor(shape: [n, k], data: out)
    }

    /// `[N, K]` → `[N, K, K]` broadcasting a per-world-per-target value over sources.
    public func expandedPerPair() -> Tensor { expandedAsColumns() }
}

// MARK: - Structural primitives
//
// These exist so that domain code never writes an index loop. Each one is a loop *here*, once,
// where it is obviously a kernel — rather than the same loop rewritten at every call site, where it
// would be indistinguishable from per-entity logic.

extension Tensor {
    /// `[N, K, K]` with zeros on the diagonal and ones elsewhere: "a rooftop is not its own target".
    public static func offDiagonal(worlds n: Int, slots k: Int) -> Tensor {
        var out = [Double](repeating: 1, count: n * k * k)
        for w in 0..<n {
            for i in 0..<k { out[w * k * k + i * k + i] = 0 }
        }
        return Tensor(shape: [n, k, k], data: out)
    }

    /// `[N, K]` with a single 1 per world at the given slot — the seed of a flood fill.
    public static func oneHot(indices: [Int], slots k: Int) -> Tensor {
        var out = [Double](repeating: 0, count: indices.count * k)
        for (w, i) in indices.enumerated() { out[w * k + i] = 1 }
        return Tensor(shape: [indices.count, k], data: out)
    }

    /// Swap the last two axes of `[N, K, K]`. Reversing an adjacency cube is a transpose, which is
    /// what lets one flood-fill serve both the forward and backward searches.
    public func transposedLastTwo() -> Tensor {
        precondition(shape.count == 3)
        let n = shape[0], k = shape[1], k2 = shape[2]
        var out = [Double](repeating: 0, count: count)
        for w in 0..<n {
            for i in 0..<k {
                for j in 0..<k2 {
                    out[w * k * k2 + j * k + i] = data[w * k * k2 + i * k2 + j]
                }
            }
        }
        return Tensor(shape: [n, k2, k], data: out)
    }

    /// Pick one slot per world out of `[N, K]`, giving `[N]`.
    public func gatherPerWorld(_ indices: [Int]) -> Tensor {
        precondition(shape.count == 2 && shape[0] == indices.count)
        let k = shape[1]
        var out = [Double](repeating: 0, count: indices.count)
        for (w, i) in indices.enumerated() { out[w] = data[w * k + i] }
        return Tensor(shape: [indices.count], data: out)
    }

    /// The flat slot indices where a mask is set, for one world. The only place the vector world is
    /// converted back into a list, and it exists purely so results can be reported.
    public func setSlots(world: Int) -> [Int] {
        precondition(shape.count == 2)
        let k = shape[1]
        return (0..<k).filter { data[world * k + $0] > 0.5 }
    }
}

// MARK: - Reductions

extension Tensor {
    /// Sum over the last axis. `[N, K, K]` → `[N, K]`, `[N, K]` → `[N]`.
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

    /// Minimum over the last axis, ignoring non-finite entries (they mean "no solution").
    public func minLastFinite() -> Tensor {
        let last = shape[shape.count - 1]
        let outer = count / last
        var out = [Double](repeating: .infinity, count: outer)
        for o in 0..<outer {
            var acc = Double.infinity
            let base = o * last
            for i in 0..<last {
                let v = data[base + i]
                if v.isFinite { acc = Swift.min(acc, v) }
            }
            out[o] = acc
        }
        return Tensor(shape: Array(shape.dropLast()), data: out)
    }

    /// "Is anything set" over the last axis — the vector form of `contains(where:)`.
    public func anyLast() -> Tensor { (sumLast() .> 0.5) }

    /// "Is everything set" over the last axis.
    public func allLast() -> Tensor {
        let last = shape[shape.count - 1]
        return (sumLast() .>= Double(last) - 0.5)
    }

    /// Reduce the MIDDLE axis of `[N, K, K]` → `[N, K]` with OR.
    ///
    /// This is the one reduction that cannot use `anyLast`, and it is the heart of the breadth-first
    /// search: `next[n, j] = OR over i of (frontier[n, i] AND adjacency[n, i, j])`. Repeating it K
    /// times floods the whole reachable set with no queue and no per-node loop.
    public func anyOverSources() -> Tensor {
        precondition(shape.count == 3)
        let n = shape[0], k = shape[1], k2 = shape[2]
        var out = [Double](repeating: 0, count: n * k2)
        for w in 0..<n {
            for i in 0..<k {
                let base = w * k * k2 + i * k2
                for j in 0..<k2 where data[base + j] > 0.5 {
                    out[w * k2 + j] = 1
                }
            }
        }
        return Tensor(shape: [n, k2], data: out)
    }
}
