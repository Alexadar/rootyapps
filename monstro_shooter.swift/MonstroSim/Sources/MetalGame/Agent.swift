import Foundation
import CoreML
import simd

// Apple-blessed agent inference: the trained policy runs via Core ML (computeUnits = .all →
// CPU/GPU/ANE) to drive the Metal game. Pure Core ML — no MLX in the game. This is the pattern
// Apple showcased at WWDC 2026 (Core AI / Core ML on-device game NPC); Core AI is the macOS-27
// successor (swap MLModel→AIModel) once that SDK ships.
//
// obs layout MUST match training (brax/env.obs, BatchWorld.buildPlayerObs):
//   [healthNorm, aliveNorm, threatX, threatY, nearestDist/1000, meanDist/1000]
final class CoreMLAgent {
    private let model: MLModel

    init?(path: String) {
        guard let compiled = try? MLModel.compileModel(at: URL(fileURLWithPath: path)) else { return nil }
        let cfg = MLModelConfiguration(); cfg.computeUnits = .all
        guard let m = try? MLModel(contentsOf: compiled, configuration: cfg) else { return nil }
        model = m
    }

    /// obs -> (move, aim). Move is tanh-bounded; aim normalized.
    func act(_ obs: [Float]) -> (move: SIMD2<Float>, aim: SIMD2<Float>) {
        guard let arr = try? MLMultiArray(shape: [NSNumber(value: obs.count)], dataType: .float32) else {
            return (.zero, SIMD2(0, 1))
        }
        for (i, v) in obs.enumerated() { arr[i] = NSNumber(value: v) }
        guard let prov = try? MLDictionaryFeatureProvider(dictionary: ["obs": MLFeatureValue(multiArray: arr)]),
              let out = try? model.prediction(from: prov),
              let o = out.featureValue(for: "action")?.multiArrayValue, o.count >= 4 else {
            return (.zero, SIMD2(0, 1))
        }
        let mv = SIMD2<Float>(tanh(o[0].floatValue), tanh(o[1].floatValue))
        var aim = SIMD2<Float>(o[2].floatValue, o[3].floatValue)
        let l = simd_length(aim); aim = l > 1e-4 ? aim / l : SIMD2(0, 1)
        return (mv, aim)
    }
}
