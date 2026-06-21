import Foundation

// MARK: - Tiny MLP (pure Swift, no dependencies)
// Capacity note: for K-nearest vector observations this game needs only a small MLP
// (tens of thousands of params). See docs for the type-embedding / set-pooling upgrade
// that scales cleanly to many monsters of many types.
public struct MLP {
    public let sizes: [Int]          // e.g. [62, 128, 128, 27]
    public var params: [Float]

    public static func paramCount(_ sizes: [Int]) -> Int {
        var n = 0
        for l in 1..<sizes.count { n += sizes[l] * sizes[l - 1] + sizes[l] }
        return n
    }

    public init(sizes: [Int], params: [Float]? = nil) {
        self.sizes = sizes
        if let p = params { self.params = p }
        else {
            // Small random init (deterministic-friendly: caller may overwrite).
            var rng = SeededGenerator(seed: 0xC0FFEE)
            let n = MLP.paramCount(sizes)
            self.params = (0..<n).map { _ in Float(Double.random(in: -0.1...0.1, using: &rng)) }
        }
    }

    public func forward(_ input: [Float]) -> [Float] {
        var x = input
        var idx = 0
        for l in 1..<sizes.count {
            let inN = sizes[l - 1], outN = sizes[l]
            var y = [Float](repeating: 0, count: outN)
            for o in 0..<outN {
                var sum = params[idx + outN * inN + o]  // bias (biases stored after weights)
                let base = idx + o * inN
                for i in 0..<inN { sum += params[base + i] * x[i] }
                y[o] = sum
            }
            if l < sizes.count - 1 { for o in 0..<outN where y[o] < 0 { y[o] = 0 } } // ReLU hidden
            idx += outN * inN + outN
            x = y
        }
        return x
    }
}

// MARK: - Neural policy
public struct NeuralPolicy: Policy {
    public var net: MLP
    public init(_ net: MLP) { self.net = net }

    public func act(_ world: World) -> SimAction {
        let out = net.forward(world.observe())
        let move = NeuralPolicy.argmax(out, 0, SimAction.moveDirs)
        let aim = NeuralPolicy.argmax(out, SimAction.moveDirs, SimAction.aimDirs)
        let shootBase = SimAction.moveDirs + SimAction.aimDirs
        let shoot = out[shootBase + 1] > out[shootBase]
        return SimAction(moveDir: move, aimDir: aim, shoot: shoot)
    }

    static func argmax(_ a: [Float], _ start: Int, _ count: Int) -> Int {
        var best = 0; var bv = a[start]
        for i in 1..<count where a[start + i] > bv { bv = a[start + i]; best = i }
        return best
    }
}

// MARK: - Evolution Strategies trainer (OpenAI-ES, mirrored sampling + rank shaping)
// Pure Swift, CPU, no autodiff. This is the "train it without Python/MLX" path.
public struct ESConfig {
    public var hidden: [Int] = [128, 128]
    public var population: Int = 64        // mirrored => 2*population evals/iter
    public var sigma: Float = 0.1
    public var learningRate: Float = 0.05
    public var iterations: Int = 30
    public init() {}
}

public enum ES {
    /// Train a policy. `fitness(net)` returns mean reward (higher is better).
    public static func train(observationSize: Int, actionSize: Int, cfg: ESConfig,
                             seed: UInt64, fitness: (MLP) -> Double,
                             onIteration: ((Int, Double) -> Void)? = nil) -> MLP {
        let sizes = [observationSize] + cfg.hidden + [actionSize]
        var rng = SeededGenerator(seed: seed)
        let n = MLP.paramCount(sizes)
        var theta = (0..<n).map { _ in Float(Double.random(in: -0.1...0.1, using: &rng)) }

        for iter in 0..<cfg.iterations {
            // Sample mirrored noise.
            var noises: [[Float]] = []
            noises.reserveCapacity(cfg.population)
            for _ in 0..<cfg.population {
                noises.append((0..<n).map { _ in Float(gaussian(&rng)) })
            }
            // Evaluate +/- each perturbation.
            var scored: [(f: Double, i: Int, sign: Float)] = []
            for (i, eps) in noises.enumerated() {
                let plus = MLP(sizes: sizes, params: add(theta, eps, cfg.sigma))
                let minus = MLP(sizes: sizes, params: add(theta, eps, -cfg.sigma))
                scored.append((fitness(plus), i, 1))
                scored.append((fitness(minus), i, -1))
            }
            // Rank-normalize fitness to weights in [-0.5, 0.5].
            let ranks = rankWeights(scored.map { $0.f })
            // Gradient estimate.
            var grad = [Float](repeating: 0, count: n)
            for (k, s) in scored.enumerated() {
                let w = Float(ranks[k]) * s.sign
                let eps = noises[s.i]
                if w == 0 { continue }
                for j in 0..<n { grad[j] += w * eps[j] }
            }
            let scale = cfg.learningRate / (Float(scored.count) * cfg.sigma)
            for j in 0..<n { theta[j] += scale * grad[j] }

            let best = scored.map { $0.f }.max() ?? 0
            onIteration?(iter, best)
        }
        return MLP(sizes: sizes, params: theta)
    }

    private static func add(_ a: [Float], _ b: [Float], _ s: Float) -> [Float] {
        var out = a
        for i in 0..<a.count { out[i] += s * b[i] }
        return out
    }

    private static func gaussian(_ rng: inout SeededGenerator) -> Double {
        // Box-Muller.
        let u1 = max(Double.random(in: 0...1, using: &rng), 1e-12)
        let u2 = Double.random(in: 0...1, using: &rng)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    /// Centered rank transform -> weights in roughly [-0.5, 0.5].
    private static func rankWeights(_ fitness: [Double]) -> [Double] {
        let n = fitness.count
        let order = fitness.enumerated().sorted { $0.element < $1.element }.map { $0.offset }
        var w = [Double](repeating: 0, count: n)
        for (rank, idx) in order.enumerated() {
            w[idx] = Double(rank) / Double(n - 1) - 0.5
        }
        return w
    }
}
