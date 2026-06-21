import Foundation
import MLX
import MLXRandom

// A small MLP whose parameters are MLXArrays, so its forward pass is just MLX kernels that run
// in-graph on the GPU alongside the sim — no CPU round-trip. Continuous outputs (no argmax/gather):
// the player net emits (moveX, moveY, aimX, aimY); we normalize on the GPU.
public struct GPUPolicy {
    public let sizes: [Int]                 // e.g. [obs, 64, 64, out]
    public var weights: [MLXArray]          // per layer: [in, out]
    public var biases: [MLXArray]           // per layer: [out]

    public init(sizes: [Int], seed: UInt64) {
        self.sizes = sizes
        var w: [MLXArray] = []; var b: [MLXArray] = []
        var key = MLXRandom.key(seed)
        for l in 1..<sizes.count {
            let (k1, k2) = MLXRandom.split(key: key); key = k2
            // small init ~ N(0, 0.1)
            w.append(MLXRandom.normal([sizes[l - 1], sizes[l]], key: k1) * 0.1)
            b.append(MLXArray.zeros([sizes[l]]))
        }
        self.weights = w; self.biases = b
    }

    public init(sizes: [Int], weights: [MLXArray], biases: [MLXArray]) {
        self.sizes = sizes; self.weights = weights; self.biases = biases
    }

    /// Forward. `x`: [..., obs] (any leading batch dims). Returns [..., out]. ReLU hidden, linear out.
    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = x
        for i in 0..<weights.count {
            h = MLX.matmul(h, weights[i]) + biases[i]
            if i < weights.count - 1 { h = MLX.maximum(h, MLXArray(Float(0))) }
        }
        return h
    }

    /// Single-sample host inference (for parity checks vs a Core ML / ANE export).
    public func predictSingle(_ obs: [Float]) -> [Float] {
        let y = self(MLXArray(obs, [1, obs.count]))
        eval(y)
        return y.asArray(Float.self)
    }

    /// Flat parameter list (for the ES trainer to perturb / rebuild).
    public var flatParams: [MLXArray] { weights + biases }
    public var paramCount: Int { sizes.indices.dropFirst().reduce(0) { $0 + sizes[$1 - 1] * sizes[$1] + sizes[$1] } }

    public func withParams(_ flat: [MLXArray]) -> GPUPolicy {
        let n = weights.count
        return GPUPolicy(sizes: sizes, weights: Array(flat[0..<n]), biases: Array(flat[n..<2 * n]))
    }

    /// Save/load (host) — eval to materialize, then read Float arrays.
    public func toData() -> Data {
        struct Saved: Codable { let sizes: [Int]; let w: [[Float]]; let b: [[Float]] }
        eval(weights + biases)
        let s = Saved(sizes: sizes, w: weights.map { $0.asArray(Float.self) }, b: biases.map { $0.asArray(Float.self) })
        return (try? JSONEncoder().encode(s)) ?? Data()
    }

    public static func fromData(_ data: Data) -> GPUPolicy? {
        struct Saved: Codable { let sizes: [Int]; let w: [[Float]]; let b: [[Float]] }
        guard let s = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
        let w = zip(s.w, Array(s.sizes.indices.dropFirst())).map { MLXArray($0.0, [s.sizes[$0.1 - 1], s.sizes[$0.1]]) }
        let b = s.b.enumerated().map { MLXArray($0.element, [s.sizes[$0.offset + 1]]) }
        return GPUPolicy(sizes: s.sizes, weights: w, biases: b)
    }

    public static func playerObsSize() -> Int { 6 }   // [healthNorm, aliveNorm, threatX, threatY, nearestDist, meanDist]
    public static func playerOutSize() -> Int { 4 }   // [moveX, moveY, aimX, aimY]
}
