import Foundation

/// The in-house vector layer. Foundation only — no Accelerate, no simd, no MLX.
///
/// Lifted from `froggo2/Kits/Reachability/ReachabilityKit/Sources/ReachabilityKit/Tensor.swift` and
/// generalised from its rooftop shapes to this game's. The rule it exists to enforce is unchanged:
///
///   **No domain code contains a loop over worlds, over trajectories, or over pairs.**
///
/// Loops live *here*, inside the elementwise kernels, and nowhere else. That is what makes batching
/// free rather than a rewrite: one level solved on its own and ten thousand candidate levels solved
/// together run the *same* code, and the leading dimension is the only difference. The playable game
/// is this program at `N = 1`.
///
/// Shapes used by this game:
///
///   `[N]`         — one value per world
///   `[N, K]`      — one value per entity, K = fixed slot capacity
///   `[N, R]`      — one value per ray or trajectory
///   `[N, R, 8]`   — geodesic state: xᵘ = (t, r, θ, φ) then covariant p_μ
///   `[N, P, 4, 4]` — one transform per portal pair
///   `[N, K, P]`   — one value per entity × portal, the crossing masks
///
/// Absent entities are *carried*, never removed: a world with fewer than K bodies keeps the empty
/// slots and masks them out. Removing them would mean ragged arrays, and ragged arrays mean loops.
///
/// `Double` throughout, and deliberately. A predicate near a boundary — "did this cross the
/// horizon", "is this still outside the ergosphere" — does not shift slightly under a Float rounding
/// difference. It flips.
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

    /// Hardware `fsqrt` — IEEE-754 correctly rounded and exactly specified, so it is bit-identical
    /// on every conforming target. One of the few library functions safe inside the determinism
    /// contract; `sin`/`cos`/`exp` are not, and live in DetMathKit instead.
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
// whole program branchless: a conditional becomes a multiply, and "if this body is absent, skip it"
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

    /// Edge detection by arithmetic — the vector form of `if justHappened`.
    ///
    /// `newlySet(now:previous:)` is `now * (1 - previous)`: one where the mask has just turned on,
    /// zero everywhere else including where it was already on. This is how a portal crossing, a
    /// horizon crossing or an ergosphere entry is detected without a branch and without a per-entity
    /// loop, at the same cost whether anything happened or not.
    public static func newlySet(now: Tensor, previous: Tensor) -> Tensor {
        now * (1.0 - previous)
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
// The move that replaces the double loop `for a in bodies { for b in bodies { ... } }`. Given
// per-body values `[N, K]`, `rows` repeats each body down a column and `cols` repeats it across a
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

    /// `[N]` → `[N, K]`, repeating each world's value across its slots.
    public func expandedPerSlot(_ k: Int) -> Tensor {
        precondition(shape.count == 1)
        let n = shape[0]
        var out = [Double](repeating: 0, count: n * k)
        for w in 0..<n {
            let v = data[w]
            for i in 0..<k { out[w * k + i] = v }
        }
        return Tensor(shape: [n, k], data: out)
    }

    /// Append a trailing axis of length `m`, repeating each value across it.
    /// `[N, K]` → `[N, K, m]`. Used to broadcast a per-entity scalar over portals.
    public func expandedLast(_ m: Int) -> Tensor {
        var out = [Double](repeating: 0, count: count * m)
        for i in 0..<count {
            let v = data[i]
            let base = i * m
            for j in 0..<m { out[base + j] = v }
        }
        return Tensor(shape: shape + [m], data: out)
    }
}

// MARK: - Component access on the last axis
//
// Geodesic state is `[N, R, 8]`: xᵘ = (t, r, θ, φ) followed by covariant p_μ. The integrator needs
// to pull a component out as `[N, R]`, do algebra on it, and put it back — without ever indexing a
// trajectory. `unstackLast` / `stackLast` are that, and they are the only sanctioned way in or out.

extension Tensor {
    /// `[.., m]` → m tensors of shape `[..]`.
    public func unstackLast() -> [Tensor] {
        let m = shape[shape.count - 1]
        let outer = count / m
        let outShape = Array(shape.dropLast())
        var parts = [[Double]](repeating: [Double](repeating: 0, count: outer), count: m)
        for o in 0..<outer {
            let base = o * m
            for c in 0..<m { parts[c][o] = data[base + c] }
        }
        return parts.map { Tensor(shape: outShape, data: $0) }
    }

    /// m tensors of shape `[..]` → `[.., m]`. The inverse of `unstackLast`.
    public static func stackLast(_ parts: [Tensor]) -> Tensor {
        precondition(!parts.isEmpty, "cannot stack nothing")
        let m = parts.count
        let outer = parts[0].count
        let outShape = parts[0].shape
        for p in parts { precondition(p.count == outer, "stackLast: ragged parts") }
        var out = [Double](repeating: 0, count: outer * m)
        for o in 0..<outer {
            let base = o * m
            for c in 0..<m { out[base + c] = parts[c].data[o] }
        }
        return Tensor(shape: outShape + [m], data: out)
    }
}

// MARK: - Structural primitives
//
// These exist so that domain code never writes an index loop. Each one is a loop *here*, once,
// where it is obviously a kernel — rather than the same loop rewritten at every call site, where it
// would be indistinguishable from per-entity logic.

extension Tensor {
    /// `[N, K, K]` with zeros on the diagonal and ones elsewhere: "a body is not its own target".
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

    /// Swap the last two axes of `[N, A, B]` → `[N, B, A]`.
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

// MARK: - Batched 4×4 transforms
//
// Portal algebra is a pile of 4×4 matrices — one per pair, per world — and applying a teleport is a
// masked matrix multiply rather than a branch. `[N, P, 4, 4]` throughout.
//
// 4×4 is also the largest matrix `simd` offers, which is worth knowing: true 4-D *spatial*
// transforms need 5×5 homogeneous matrices and are hand-rolled on top of these routines, not
// inherited from the SDK.

extension Tensor {
    /// Row-major `[.., 4, 4]` × `[.., 4, 4]` → `[.., 4, 4]`, batched over every leading axis.
    public static func matmul4x4(_ a: Tensor, _ b: Tensor) -> Tensor {
        precondition(a.shape.suffix(2) == [4, 4] && b.shape.suffix(2) == [4, 4],
                     "matmul4x4 needs [.., 4, 4], got \(a.shape) and \(b.shape)")
        precondition(a.count == b.count, "matmul4x4 batch mismatch: \(a.shape) vs \(b.shape)")
        let batches = a.count / 16
        var out = [Double](repeating: 0, count: a.count)
        for m in 0..<batches {
            let base = m * 16
            for i in 0..<4 {
                for j in 0..<4 {
                    var acc = 0.0
                    for k in 0..<4 { acc += a.data[base + i * 4 + k] * b.data[base + k * 4 + j] }
                    out[base + i * 4 + j] = acc
                }
            }
        }
        return Tensor(shape: a.shape, data: out)
    }

    /// Apply `[.., 4, 4]` to homogeneous points `[.., 4]` → `[.., 4]`.
    public static func apply4x4(_ m: Tensor, to v: Tensor) -> Tensor {
        precondition(m.shape.suffix(2) == [4, 4] && v.shape.suffix(1) == [4])
        let batches = v.count / 4
        precondition(m.count / 16 == batches, "apply4x4 batch mismatch")
        var out = [Double](repeating: 0, count: v.count)
        for b in 0..<batches {
            let mb = b * 16, vb = b * 4
            for i in 0..<4 {
                var acc = 0.0
                for k in 0..<4 { acc += m.data[mb + i * 4 + k] * v.data[vb + k] }
                out[vb + i] = acc
            }
        }
        return Tensor(shape: v.shape, data: out)
    }

    /// `[N, P, 4, 4]` of identity matrices.
    public static func identity4x4(batches: [Int]) -> Tensor {
        let n = batches.reduce(1, *)
        var out = [Double](repeating: 0, count: n * 16)
        for b in 0..<n {
            let base = b * 16
            for i in 0..<4 { out[base + i * 4 + i] = 1 }
        }
        return Tensor(shape: batches + [4, 4], data: out)
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
    /// This is the one reduction that cannot use `anyLast`, and it is the heart of a breadth-first
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
