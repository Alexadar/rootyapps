import Foundation
import MLX
import MLXRandom

// Evolution Strategies over MLX policy params — no autodiff. Mirrored sampling + centered-rank
// shaping (OpenAI-ES). Each candidate's fitness is one on-device episode batch (N envs = N seeds),
// so the whole evaluation stays on the GPU; only the scalar fitnesses sync back.
public enum GPUES {
    public struct Config {
        public var population: Int = 16
        public var sigma: Float = 0.1
        public var learningRate: Float = 0.05
        public var iterations: Int = 20
        public init() {}
    }

    /// `fitness(net)` runs a rollout and returns a scalar (higher better).
    public static func train(net0: GPUPolicy, cfg: Config, seed: UInt64,
                             fitness: (GPUPolicy) -> Float,
                             onIteration: ((Int, Float, Float) -> Void)? = nil) -> GPUPolicy {
        var theta = net0.flatParams
        eval(theta)
        var key = MLXRandom.key(seed)

        for iter in 0..<cfg.iterations {
            // sample mirrored noise sets
            var noises: [[MLXArray]] = []
            for _ in 0..<cfg.population {
                var ns: [MLXArray] = []
                for p in theta {
                    let (k1, k2) = MLXRandom.split(key: key); key = k2
                    ns.append(MLXRandom.normal(p.shape, key: k1))
                }
                eval(ns)
                noises.append(ns)
            }
            // evaluate ±
            var scored: [(f: Float, i: Int, sign: Float)] = []
            for (i, ns) in noises.enumerated() {
                let plus = net0.withParams(zip(theta, ns).map { $0 + cfg.sigma * $1 })
                let minus = net0.withParams(zip(theta, ns).map { $0 - cfg.sigma * $1 })
                scored.append((fitness(plus), i, 1))
                scored.append((fitness(minus), i, -1))
            }
            // centered-rank weights
            let ranks = rankWeights(scored.map { Double($0.f) })
            var grad = theta.map { MLXArray.zeros($0.shape) }
            for (k, s) in scored.enumerated() {
                let w = Float(ranks[k]) * s.sign
                if w == 0 { continue }
                for j in theta.indices { grad[j] = grad[j] + noises[s.i][j] * w }
            }
            let scale = cfg.learningRate / (Float(scored.count) * cfg.sigma)
            theta = zip(theta, grad).map { $0 + scale * $1 }
            eval(theta)

            // True learning curve = fitness of the CENTER policy (theta), not the noisy population.
            let center = fitness(net0.withParams(theta))
            onIteration?(iter, center, scored.map { $0.f }.max() ?? 0)
        }
        return net0.withParams(theta)
    }

    private static func rankWeights(_ fitness: [Double]) -> [Double] {
        let n = fitness.count
        guard n > 1 else { return [0] }
        let order = fitness.enumerated().sorted { $0.element < $1.element }.map { $0.offset }
        var w = [Double](repeating: 0, count: n)
        for (rank, idx) in order.enumerated() { w[idx] = Double(rank) / Double(n - 1) - 0.5 }
        return w
    }
}
