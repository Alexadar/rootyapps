import Foundation
import GenerationKit
import TaskKit

/// Works out which model is actually installed.
///
/// ### Why the model declares itself
///
/// The pipeline arrives as a downloadable asset pack, converted by a script in another repository.
/// The app cannot know what a future pack contains, so the pack says so: the converter writes a
/// `model.json` beside the compiled models, and this reads it. Anything else — inferring from file
/// names, matching sizes — is the app guessing about bytes it did not produce, and it goes wrong
/// silently the first time a conversion changes.
///
/// ### And why there is still a fallback
///
/// Packs converted before `model.json` existed are on at least one device already (this one). Those
/// are recognised by their shape, which for `sd15cn` is unambiguous: a controlled unet plus a
/// ControlNet directory. The fallback is deliberately narrow — it identifies the one model that
/// predates the declaration and nothing else, so it cannot quietly mislabel a future pack.
enum ModelCatalog {

    /// What the declaration file looks like. Only `id` is required; everything else about a model is
    /// already known to the build that supports it.
    private struct Declaration: Decodable {
        let id: String
    }

    static let declarationFilename = "model.json"

    /// The model installed at `resourcesURL`, or `nil` if there is nothing recognisable there.
    ///
    /// `nil` is a real answer, not a failure: it is what a pack from a newer build of the app looks
    /// like to an older one, and the honest response is to refuse to use it rather than to run it as
    /// if it were something else.
    static func installed(at resourcesURL: URL) -> ModelIdentity? {
        // **A declaration is final**, including when it is unrecognisable. Falling back to inference
        // when the id is unknown would take a pack that explicitly said what it was and label it as
        // the one model this build happens to recognise — which is exactly the mislabelling the
        // declaration exists to prevent. Inference is only for packs that say nothing at all.
        let url = resourcesURL.appendingPathComponent(declarationFilename)
        guard let data = try? Data(contentsOf: url) else {
            return inferred(at: resourcesURL)
        }
        guard let declaration = try? JSONDecoder().decode(Declaration.self, from: data) else {
            return nil
        }
        // An id this build does not know is not an error — it is a pack from a newer app.
        return ModelIdentity.known(id: declaration.id)
    }

    /// Every model installed right now, by the subtask it serves — what a job's recorded models are
    /// checked against on the next launch.
    ///
    /// Lists what is *available*, not what any particular job used: a generation that never upscaled
    /// does not become unresumable because an upscaler is present. The asymmetry lives in
    /// `areAllStillInstalled(among:)`.
    static func installedModels() -> [ModelUse] {
        var found: [ModelUse] = []

        if let resources = CoreMLImageGenerator.bundledResourcesURL(),
           let model = installed(at: resources) {
            let fingerprint = JobStore.fingerprint(ofModelAt: resources)
            // Stages 1 and 3 are the same pack today. Recorded as two entries rather than one
            // because they are different subtasks, and the day they are served by different packs
            // the manifests written before it must still mean what they said.
            found.append(ModelUse(role: .generate, id: model.id, fingerprint: fingerprint))
            if model.hasControlNet {
                found.append(ModelUse(role: .refine, id: model.id, fingerprint: fingerprint))
            }
        }

        if let url = Upscaler.bundledModelURL(), let id = Upscaler.installedID {
            found.append(ModelUse(role: .upscale, id: id,
                                  fingerprint: JobStore.fingerprint(ofModelAt: url)))
        }
        return found
    }

    /// What one subtask is served by right now, or `nil` if nothing can do it.
    static func installedModel(for role: ModelUse.Role) -> ModelUse? {
        installedModels().first { $0.role == role }
    }

    /// The one model that predates `model.json`: SD 1.5 converted with `--unet-support-controlnet`,
    /// shipping a Tile ControlNet. Recognised by exactly that shape and nothing looser.
    private static func inferred(at resourcesURL: URL) -> ModelIdentity? {
        let manager = FileManager.default
        let hasControlledUnet = manager.fileExists(
            atPath: resourcesURL.appendingPathComponent("ControlledUnet.mlmodelc").path)
        let controlNets = (try? manager.contentsOfDirectory(
            atPath: resourcesURL.appendingPathComponent("controlnet").path)) ?? []
        let hasTileControlNet = controlNets.contains { $0.lowercased().contains("tile") }

        guard hasControlledUnet, hasTileControlNet else { return nil }
        return .sd15cn
    }
}
