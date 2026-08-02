import Foundation

/// The trained artist DEALER: a tiny single-query attention network that,
/// conditioned on [difficulty, week, session summary] and a K=8 memory of its
/// own recent deals, emits distribution parameters for the next candidate
/// pair. This is the shipped adaptive world generator (world_coevolved.json,
/// arch "pre-qkv memory (deal-only tokens)": memory tokens are the 13-dim
/// dealt-artist features, giving n_params = 4024).
public struct Dealer {
    public static let ctxDim = 8
    public static let memK = 8
    public static let memDim = 13
    public static let dEmb = 16
    public static let hidden = 32
    public static let outPerCand = 36
    /// (name, rows, cols) in flat-vector order; biases are (1, n).
    static let shapes: [(String, Int, Int)] = [
        ("Wm", memDim, dEmb), ("bm", 1, dEmb),
        ("Wq", ctxDim, dEmb), ("bq", 1, dEmb),
        ("Wv", memDim, dEmb), ("bv", 1, dEmb),
        ("Wh", 2 * dEmb, hidden), ("bh", 1, hidden),
        ("Wo", hidden, 2 * outPerCand), ("bo", 1, 2 * outPerCand),
    ]
    public static var paramCount: Int { shapes.reduce(0) { $0 + $1.1 * $1.2 } }
    static let maskNeg = -1e4

    let w: [String: [[Double]]]   // row-major matrices; biases as single row

    public init(params: [Double]) {
        precondition(params.count == Self.paramCount,
                     "dealer params \(params.count) != \(Self.paramCount)")
        var w: [String: [[Double]]] = [:]
        var i = 0
        for (name, r, c) in Self.shapes {
            var m = [[Double]]()
            for _ in 0..<r {
                m.append(Array(params[i..<(i + c)]))
                i += c
            }
            w[name] = m
        }
        self.w = w
    }

    static func matVec(_ x: [Double], _ m: [[Double]], _ b: [[Double]]) -> [Double] {
        let cols = b[0].count
        var out = b[0]
        for i in 0..<x.count where x[i] != 0 {
            let row = m[i]
            for j in 0..<cols { out[j] += x[i] * row[j] }
        }
        return out
    }

    /// Deterministic forward: ctx [8], memory [K][13], used [K] -> raw [72].
    public func forward(ctx: [Double], memory: [[Double]], used: [Double]) -> [Double] {
        let q = Self.matVec(ctx, w["Wq"]!, w["bq"]!)
        var scores = [Double](repeating: 0, count: Self.memK)
        var values = [[Double]]()
        for j in 0..<Self.memK {
            let k = Self.matVec(memory[j], w["Wm"]!, w["bm"]!)
            values.append(Self.matVec(memory[j], w["Wv"]!, w["bv"]!))
            let dot = zip(k, q).reduce(0) { $0 + $1.0 * $1.1 }
            scores[j] = used[j] > 0.5 ? dot / Double(Self.dEmb).squareRoot() : Self.maskNeg
        }
        let mx = scores.max()!
        var weights = (0..<Self.memK).map { exp(scores[$0] - mx) * used[$0] }
        let denom = weights.reduce(0, +)
        if denom > 0 { weights = weights.map { $0 / denom } } else { weights = weights.map { _ in 0 } }
        var context = [Double](repeating: 0, count: Self.dEmb)
        for j in 0..<Self.memK where weights[j] != 0 {
            for o in 0..<Self.dEmb { context[o] += weights[j] * values[j][o] }
        }
        let h = Self.matVec(q + context, w["Wh"]!, w["bh"]!).map { max(0, $0) }
        return Self.matVec(h, w["Wo"]!, w["bo"]!)
    }

    static func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-x)) }
    static func softplus(_ x: Double) -> Double { x > 30 ? x : log1p(exp(x)) }

    /// Sampled candidate fields decoded from one 36-value output block.
    public struct Sampled {
        public let stats: [Double]
        public let genre: Int
        public let archetype: Int
        public let traitScore: Double
        public let traitChaos: Double
        /// 13-dim memory-token features of this deal.
        public var memoryToken: [Double] {
            stats.map { ($0 - 50) / 40 }
                + [Double(genre) / 6.0, Double(archetype) / 8.0, traitScore / 10, traitChaos / 10]
        }
    }

    public func sample(block r: ArraySlice<Double>, rng: inout GameRandom) -> Sampled {
        let b = Array(r)
        var stats = [Double]()
        for i in 0..<9 {
            let mu = Self.sigmoid(b[i]) * 80 + 10
            let sig = clamp(Self.softplus(b[9 + i]), 1.0, 15.0)
            stats.append(clamp(tsRound(mu + sig * rng.gaussian()), 10, 90))
        }
        let genreProbs = softmax(Array(b[18..<24]))
        let genre = rng.weightedIndex(genreProbs)
        let archProbs = softmax(Array(b[24..<32]))
        let arch = rng.weightedIndex(archProbs)
        let ts = clamp(tanh(b[32]) * 15 + clamp(Self.softplus(b[33]), 0.5, 8.0) * rng.gaussian(), -15, 21)
        let tc = clamp(Self.sigmoid(b[34]) * 10 + clamp(Self.softplus(b[35]), 0.3, 5.0) * rng.gaussian(), 0, 10)
        return Sampled(stats: stats, genre: genre, archetype: arch, traitScore: ts, traitChaos: tc)
    }

    func softmax(_ x: [Double]) -> [Double] {
        let mx = x.max()!
        let e = x.map { exp($0 - mx) }
        let s = e.reduce(0, +)
        return e.map { $0 / s }
    }
}

/// Per-session deal memory: ring of the K=8 most recent dealt-artist tokens.
public struct DealerMemory {
    public private(set) var tokens: [[Double]]
    public private(set) var used: [Double]

    public init() {
        tokens = Array(repeating: [Double](repeating: 0, count: Dealer.memDim), count: Dealer.memK)
        used = [Double](repeating: 0, count: Dealer.memK)
    }

    /// Shift the ring left by 2 and append the freshly dealt pair.
    public mutating func push(_ pair: [[Double]]) {
        tokens = Array(tokens[2...]) + pair
        used = Array(used[2...]) + [1, 1]
    }
}
