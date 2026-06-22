import Foundation
import CoreML

// ANE/Core ML inference connector — the "where it makes sense" path.
//
// This is NOT for the reactive per-tick policy (that stays GPU-in-graph to avoid a per-tick
// GPU<->ANE handoff). It's the connector for a DECOUPLED / infrequent / shipped model: load a
// Core ML model and let Core ML place it on the Apple Neural Engine (`computeUnits = .all`).
//
// The model artifact (.mlpackage) is produced OFFLINE from the same JSON weights via
// tools/export_coreml.py (needs coremltools). The weights are the backend-agnostic lego connector:
// same player.json -> GPUPolicy (MLX, now) / CoreMLPolicy (ANE, here) / JAX (Brax, next).
public final class CoreMLPolicy {
    private let model: MLModel
    private let inputName: String
    private let outputName: String

    /// Load a `.mlpackage` or `.mlmodel`; `.all` lets Core ML schedule the ANE when eligible.
    public init(url: URL, inputName: String = "obs", outputName: String = "action",
                computeUnits: MLComputeUnits = .all) throws {
        let compiled = try MLModel.compileModel(at: url)
        let cfg = MLModelConfiguration()
        cfg.computeUnits = computeUnits
        self.model = try MLModel(contentsOf: compiled, configuration: cfg)
        self.inputName = inputName
        self.outputName = outputName
    }

    /// Single-sample inference (the decoupled use case). obs -> action.
    public func predict(_ obs: [Float]) throws -> [Float] {
        let arr = try MLMultiArray(shape: [NSNumber(value: obs.count)], dataType: .float32)
        for (i, v) in obs.enumerated() { arr[i] = NSNumber(value: v) }
        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: arr)])
        let out = try model.prediction(from: provider)
        guard let o = out.featureValue(for: outputName)?.multiArrayValue else { return [] }
        return (0..<o.count).map { o[$0].floatValue }
    }
}
