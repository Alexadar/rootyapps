import Foundation
import MLX
import MLXRandom

/// Minimal smoke test that MLX resolves and runs on the Metal GPU.
public enum GPUSmoke {
    /// Sum N random floats on the GPU and return the result (forces eval).
    public static func run(n: Int = 1_000_000) -> Float {
        MLXRandom.seed(0)
        let a = MLXRandom.uniform(0.0 ..< 1.0, [n])
        let s = a.sum()
        eval(s)
        return s.item(Float.self)
    }
}
