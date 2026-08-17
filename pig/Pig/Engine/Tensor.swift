import Foundation

/// The in-house vector layer. Foundation only — no Accelerate, no simd, no MLX.
///
/// Lifted from `bigpinkcat.swift/Kits/Tensor/TensorKit/Sources/TensorKit/Tensor.swift`, which was
/// itself lifted from `froggo2`'s `ReachabilityKit`. The rule it exists to enforce is unchanged:
///
///   **No domain code contains a loop over worlds or over slots.**
///
/// Loops live *here*, inside the elementwise kernels, and nowhere else. That is what makes batching
/// free rather than a rewrite: one pig walking and ten thousand pigs walking run the *same* code, and
/// the leading dimension is the only difference. The playable game is this program at `N = 1`.
///
/// Shapes used by this game:
///
///   `[N]`     — one value per world
///   `[N, K]`  — one value per food pile, K = fixed slot capacity
///
/// Absent piles are *carried*, never removed: a world with fewer than K piles keeps the empty slots
/// and masks them out. Removing them would mean ragged arrays, and ragged arrays mean loops.
///
/// `Double` throughout. A predicate near a boundary — "is the snout touching this pile" — does not
/// shift slightly under a Float rounding difference. It flips.
struct Tensor: Sendable, Equatable {
    let shape: [Int]
    var data: [Double]

    init(shape: [Int], data: [Double]) {
        precondition(shape.reduce(1, *) == data.count,
                     "shape \(shape) does not describe \(data.count) elements")
        self.shape = shape
        self.data = data
    }

    init(repeating value: Double, shape: [Int]) {
        self.init(shape: shape, data: [Double](repeating: value, count: shape.reduce(1, *)))
    }

    static func zeros(_ shape: [Int]) -> Tensor { Tensor(repeating: 0, shape: shape) }
    static func ones(_ shape: [Int]) -> Tensor { Tensor(repeating: 1, shape: shape) }

    var count: Int { data.count }
    subscript(i: Int) -> Double { data[i] }

    func reshaped(_ newShape: [Int]) -> Tensor { Tensor(shape: newShape, data: data) }

    /// Trailing extent — the slot count of an `[N, K]`, or 1 for an `[N]`.
    var lastDim: Int { shape.count > 1 ? shape[shape.count - 1] : 1 }
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

    static func + (a: Tensor, b: Tensor) -> Tensor { zip(a, b, +) }
    static func - (a: Tensor, b: Tensor) -> Tensor { zip(a, b, -) }
    static func * (a: Tensor, b: Tensor) -> Tensor { zip(a, b, *) }
    static func / (a: Tensor, b: Tensor) -> Tensor { zip(a, b, /) }

    static func + (a: Tensor, s: Double) -> Tensor { a.map { $0 + s } }
    static func - (a: Tensor, s: Double) -> Tensor { a.map { $0 - s } }
    static func * (a: Tensor, s: Double) -> Tensor { a.map { $0 * s } }
    static func / (a: Tensor, s: Double) -> Tensor { a.map { $0 / s } }
    static func + (s: Double, a: Tensor) -> Tensor { a.map { s + $0 } }
    static func - (s: Double, a: Tensor) -> Tensor { a.map { s - $0 } }
    static func * (s: Double, a: Tensor) -> Tensor { a.map { s * $0 } }
    static func / (s: Double, a: Tensor) -> Tensor { a.map { s / $0 } }
    static prefix func - (a: Tensor) -> Tensor { a.map { -$0 } }

    /// Hardware `fsqrt` — IEEE-754 correctly rounded, so it is bit-identical on every conforming
    /// target. `sin`/`cos`/`atan2` below are NOT in that class; see the note on `Trig`.
    var squareRoot: Tensor { map { $0 < 0 ? .nan : $0.squareRoot() } }
    var absolute: Tensor { map { Swift.abs($0) } }
    var rounded: Tensor { map { ($0).rounded() } }
    var floored: Tensor { map { ($0).rounded(.down) } }
    var sign: Tensor { map { $0 > 0 ? 1 : ($0 < 0 ? -1 : 0) } }

    /// Integer powers only, evaluated as repeated multiplication so it stays inside the correctly
    /// rounded operations. `pow` is not one of them, and this is used to sharpen a footfall pulse —
    /// a place where a one-ulp difference between OS versions would be a different game.
    func raisedTo(_ p: Int) -> Tensor {
        precondition(p >= 0, "raisedTo() is for integer powers, not roots")
        return map { x in
            var acc = 1.0
            for _ in 0..<p { acc *= x }
            return acc
        }
    }

    func clamped(min lo: Double, max hi: Double) -> Tensor {
        map { Swift.min(Swift.max($0, lo), hi) }
    }

    static func minimum(_ a: Tensor, _ b: Tensor) -> Tensor { zip(a, b, Swift.min) }
    static func maximum(_ a: Tensor, _ b: Tensor) -> Tensor { zip(a, b, Swift.max) }
    func minimum(_ s: Double) -> Tensor { map { Swift.min($0, s) } }
    func maximum(_ s: Double) -> Tensor { map { Swift.max($0, s) } }

    /// Smoothstep, the only easing this engine needs, and the reason nothing here calls `exp`.
    func smoothstep(_ lo: Double, _ hi: Double) -> Tensor {
        map { x in
            let t = Swift.min(Swift.max((x - lo) / (hi - lo), 0), 1)
            return t * t * (3 - 2 * t)
        }
    }
}

// MARK: - Trigonometry
//
// Foundation's `sin`/`cos`/`atan2` are NOT correctly rounded and may differ by an ulp between OS
// versions. That is inside every physical tolerance in this game, and this POC accepts it — but the
// moment a golden state hash exists, these three route through `DetMathKit` (FDLIBM/Cephes
// coefficients over correctly-rounded ops), exactly as `bigpinkcat.swift` does. This comment is the
// marker for that swap; nothing else in the engine calls a transcendental.

extension Tensor {
    var sine: Tensor { map { Foundation.sin($0) } }
    var cosine: Tensor { map { Foundation.cos($0) } }

    static func atan2(_ y: Tensor, _ x: Tensor) -> Tensor {
        zip(y, x) { Foundation.atan2($0, $1) }
    }

    /// Wrap into (−π, π]. `round` is exact, so this is the one safe way to difference two angles.
    var wrappedToPi: Tensor {
        let twoPi = 2 * Double.pi
        return self - (self / twoPi).rounded * twoPi
    }
}

// MARK: - Masks
//
// A mask is a Tensor of 0.0 / 1.0. Keeping masks as numbers rather than Bools is what makes the whole
// program branchless: a conditional becomes a multiply, and "if this pile is absent, skip it" becomes
// "multiply its contribution by zero" — which costs the same whether it is taken or not.

infix operator .< : ComparisonPrecedence
infix operator .<= : ComparisonPrecedence
infix operator .> : ComparisonPrecedence
infix operator .>= : ComparisonPrecedence
infix operator .&& : LogicalConjunctionPrecedence
infix operator .|| : LogicalDisjunctionPrecedence

extension Tensor {
    static func .< (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { $0 < $1 ? 1 : 0 } }
    static func .<= (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { $0 <= $1 ? 1 : 0 } }
    static func .> (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { $0 > $1 ? 1 : 0 } }
    static func .>= (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { $0 >= $1 ? 1 : 0 } }

    static func .< (a: Tensor, s: Double) -> Tensor { a.map { $0 < s ? 1 : 0 } }
    static func .<= (a: Tensor, s: Double) -> Tensor { a.map { $0 <= s ? 1 : 0 } }
    static func .> (a: Tensor, s: Double) -> Tensor { a.map { $0 > s ? 1 : 0 } }
    static func .>= (a: Tensor, s: Double) -> Tensor { a.map { $0 >= s ? 1 : 0 } }

    static func .&& (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { ($0 > 0.5 && $1 > 0.5) ? 1 : 0 } }
    static func .|| (a: Tensor, b: Tensor) -> Tensor { zip(a, b) { ($0 > 0.5 || $1 > 0.5) ? 1 : 0 } }
    var not: Tensor { map { $0 > 0.5 ? 0 : 1 } }

    /// The branchless conditional. `mask ? a : b`, elementwise.
    static func which(_ mask: Tensor, _ a: Tensor, _ b: Tensor) -> Tensor {
        precondition(mask.count == a.count && a.count == b.count, "which(): shape mismatch")
        var out = a.data
        for i in 0..<out.count { out[i] = mask.data[i] > 0.5 ? a.data[i] : b.data[i] }
        return Tensor(shape: a.shape, data: out)
    }

    static func which(_ mask: Tensor, _ a: Tensor, _ b: Double) -> Tensor {
        which(mask, a, Tensor(repeating: b, shape: a.shape))
    }

    static func which(_ mask: Tensor, _ a: Double, _ b: Tensor) -> Tensor {
        which(mask, Tensor(repeating: a, shape: b.shape), b)
    }

    static func which(_ mask: Tensor, _ a: Double, _ b: Double) -> Tensor {
        which(mask, Tensor(repeating: a, shape: mask.shape), Tensor(repeating: b, shape: mask.shape))
    }
}

// MARK: - The slot axis
//
// Everything below is what replaces a variable-length list of entities. `[N]` values broadcast down
// the slot axis, `[N, K]` values reduce back to `[N]`, and a write to "the first free slot" is an
// argmin plus a one-hot — which is a scatter at fixed cost, with nothing to resize.

extension Tensor {
    /// `[N]` → `[N, K]`, repeating each world's value across its slots.
    func spread(_ k: Int) -> Tensor {
        let n = count
        var out = [Double](repeating: 0, count: n * k)
        for i in 0..<n {
            let v = data[i]
            for j in 0..<k { out[i * k + j] = v }
        }
        return Tensor(shape: [n, k], data: out)
    }

    /// `[N, K]` → `[N]`.
    func sumSlots() -> Tensor {
        let k = lastDim, n = count / k
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var s = 0.0
            for j in 0..<k { s += data[i * k + j] }
            out[i] = s
        }
        return Tensor(shape: [n], data: out)
    }

    func maxSlots() -> Tensor {
        let k = lastDim, n = count / k
        var out = [Double](repeating: -.infinity, count: n)
        for i in 0..<n {
            var m = -Double.infinity
            for j in 0..<k { m = Swift.max(m, data[i * k + j]) }
            out[i] = m
        }
        return Tensor(shape: [n], data: out)
    }

    func minSlots() -> Tensor {
        let k = lastDim, n = count / k
        var out = [Double](repeating: .infinity, count: n)
        for i in 0..<n {
            var m = Double.infinity
            for j in 0..<k { m = Swift.min(m, data[i * k + j]) }
            out[i] = m
        }
        return Tensor(shape: [n], data: out)
    }

    /// Index of the smallest element in each row. Ties resolve to the lowest index, which is what
    /// makes "the first free slot" deterministic.
    func argMinSlots() -> Tensor {
        let k = lastDim, n = count / k
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var best = Double.infinity, at = 0
            for j in 0..<k where data[i * k + j] < best { best = data[i * k + j]; at = j }
            out[i] = Double(at)
        }
        return Tensor(shape: [n], data: out)
    }

    /// `[N, K]` where every element is its own slot index. The ramp that makes "the first three
    /// slots" expressible as a comparison instead of as a loop.
    static func lanes(batch n: Int, slots k: Int) -> Tensor {
        var out = [Double](repeating: 0, count: n * k)
        for i in 0..<n {
            for j in 0..<k { out[i * k + j] = Double(j) }
        }
        return Tensor(shape: [n, k], data: out)
    }

    /// `[N]` of indices → `[N, K]` one-hot. The scatter that replaces `array.append`.
    static func oneHot(_ index: Tensor, slots k: Int) -> Tensor {
        let n = index.count
        var out = [Double](repeating: 0, count: n * k)
        for i in 0..<n {
            let j = Int(index.data[i])
            if j >= 0 && j < k { out[i * k + j] = 1 }
        }
        return Tensor(shape: [n, k], data: out)
    }

    /// One world's row, as host values.
    func row(_ i: Int) -> [Double] {
        let k = lastDim
        return Array(data[(i * k)..<((i + 1) * k)])
    }
}
