import CoreML
import Foundation

/// Lets one **controlled** unet serve plain text-to-image as well as tile refine.
///
/// Not Apple's code — an addition alongside it, so the vendored sources stay a straight copy plus a
/// single widened access level and upstream fixes can be re-applied by re-copying.
///
/// ### Why this exists
///
/// A ControlNet's contribution enters the unet by being *added* to its skip connections. Feeding
/// zeros therefore adds nothing, and the controlled unet reduces exactly to the plain one. That is
/// not a claim about maths on paper — it was checked against the converted `.mlmodelc` files on
/// identical inputs and came back **bit-identical** (max abs diff 0.000000; see
/// `aisixteen.models/scripts/prove_single_unet.py`).
///
/// The payoff is that the app ships **one** unet instead of two: 618 MB less to download, and one
/// fewer model resident on a device where memory is the binding constraint.
///
/// The shapes are read from the model's own description rather than derived from the latent size,
/// because they are not uniform — thirteen tensors spanning four resolutions and three channel
/// counts, in an order the unet cares about. Computing them by hand would be a table to get wrong.
extension Unet {

    /// Zero tensors for every `additional_residual_*` input this unet declares, or `nil` if it
    /// declares none — in which case it is a plain unet and needs nothing.
    ///
    /// Built once and reused across steps: allocating thirteen tensors per step, twenty-eight times
    /// a generation, is pure waste on a device already short of memory.
    public func zeroResidualsIfNeeded() throws -> [[String: MLShapedArray<Float32>]]? {
        guard let description = try firstModelDescription() else { return nil }

        let residualInputs = description.inputDescriptionsByName
            .filter { $0.key.hasPrefix("additional_residual") }
        guard !residualInputs.isEmpty else { return nil }

        var zeros: [String: MLShapedArray<Float32>] = [:]
        for (name, input) in residualInputs {
            guard let constraint = input.multiArrayConstraint else { continue }
            let shape = constraint.shape.map(\.intValue)
            zeros[name] = MLShapedArray<Float32>(repeating: 0, shape: shape)
        }
        guard zeros.count == residualInputs.count else {
            throw UnetResidualError.unreadableShapes(expected: residualInputs.count, got: zeros.count)
        }

        // The unet is called once per latent sample in the batch, and each call wants its own
        // dictionary — the batch is classifier-free guidance, so two for a normal generation.
        let batch = max(latentSampleShape.first ?? 1, 1)
        return Array(repeating: zeros, count: batch)
    }

    /// True when this unet was converted with `--unet-support-controlnet`.
    public var expectsControlNetResiduals: Bool {
        ((try? firstModelDescription()) ?? nil)?
            .inputDescriptionsByName.keys.contains { $0.hasPrefix("additional_residual") } ?? false
    }

    private func firstModelDescription() throws -> MLModelDescription? {
        // `models` is internal to this module, which is precisely why this file lives inside it.
        try models.first?.perform { $0.modelDescription }
    }
}

public enum UnetResidualError: Error {
    case unreadableShapes(expected: Int, got: Int)
}
