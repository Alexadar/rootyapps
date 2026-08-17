import Foundation
import CoreGraphics
import EnhanceKit
import RecipeKit
import DiffusionRuntime

/// The real pass, behind the seam.
///
/// Everything above `PhotoEnhancer` is unchanged from the mock build — this type exists to translate
/// between Studio's vocabulary (a 0–100 rail, four named detents, steps) and the shared runtime's
/// (a denoise fraction, tiles, per-step progress). That translation is the whole job; the diffusion
/// lives in `../aisixteen.models/swift/AISixteenModels`.
///
/// ⚠️ **Tile ControlNet conditions on the tile itself.** Studio has no conditioning image to compute
/// — unlike Architecture, which builds a depth map first. `.theTileItself` is the entire difference.
final class StudioEnhancer: PhotoEnhancer {

    /// Fixed. **There is no prompt field in this app and there never will be** — that is the
    /// Guideline 4.3 firewall against the sibling. This string is conditioning, not user input, and
    /// it deliberately describes a *photograph* rather than a subject: the model is being asked to
    /// resolve what is already there, not to imagine something.
    static let conditioningPrompt =
        "a sharp, clean photograph, natural detail, true to life, high quality"
    /// Steers away from the failure the category is judged on — a face that is no longer the
    /// person's face.
    static let negativePrompt =
        "blurry, oversharpened, waxy skin, distorted face, extra fingers, artifacts, watermark"

    let plan: EnhancePlan
    private let pass: TiledControlNetPass
    private let settings: TiledControlNetPass.Settings
    /// The rail position this enhancer's schedule was built for.
    ///
    /// ⚠️ Held because `enhance(strength:)` **cannot** honour a different one. The step count is
    /// fixed at init — it is what `plan` already told the interface, and what the progress capsule
    /// has been counting against since its first frame. Recomputing the schedule mid-pass would
    /// make the capsule's denominator a lie; ignoring the mismatch and reporting the *argument* as
    /// `renderedStrength` would be worse, because the recipe's blend is `strength / rendered` and a
    /// wrong `rendered` silently rescales every later dial position.
    private let builtFor: Strength
    private let cancelled = EnhanceCancelFlag()

    /// - Returns: `nil` when the pack is not on this machine, which is a normal state — the model
    ///   ships as a downloadable pack and the app runs against the mock until it arrives.
    init?(resources: URL, strength: Strength, photoWidth: Int, photoHeight: Int) {
        guard let controlNet = ControlNetCatalog.name(of: .tile, at: resources) else { return nil }
        guard let denoise = StrengthCurve.denoise(for: strength) else { return nil }

        var settings = TiledControlNetPass.Settings()
        settings.strength = denoise
        settings.steps = StrengthCurve.steps
        self.settings = settings
        self.builtFor = strength
        self.pass = TiledControlNetPass(resourcesAt: resources, controlNet: controlNet)

        // ⚠️ Computed **before** the run, from the size the pass will actually see. The total is
        // arithmetic — no model, no I/O — so the capsule can show an honest "step 1 of N" from the
        // first frame instead of guessing and correcting itself.
        let working = Self.workingSize(width: photoWidth, height: photoHeight,
                                       side: settings.workingSide)
        let computed = TiledControlNetPass.plan(for: settings,
                                                width: working.width,
                                                height: working.height)
        self.plan = EnhancePlan(totalSteps: max(1, computed.totalSteps),
                                previewCadence: max(1, computed.stepsPerTile))
    }

    func cancel() { cancelled.set() }

    func enhance(photo: CGImage,
                 strength: Double,
                 mask: CGImage?,
                 seed: UInt32?,
                 progress: @escaping (EnhanceProgress) -> Void) async throws -> EnhancedPhoto {
        // The schedule is already fixed (see `builtFor`). A caller handing a different strength has
        // reused an enhancer across passes, which the factory does not do — loud in development,
        // and in release the pass still renders at the strength it planned rather than silently
        // recording one it did not.
        assert(strength == builtFor.value,
               "enhancer built for \(builtFor.value) asked to run at \(strength)")

        cancelled.reset()
        let chosenSeed = seed ?? UInt32.randomSeed()
        let settings = self.settings
        let pass = self.pass
        let plan = self.plan
        let cancelled = self.cancelled

        // ⚠️ The mask is not passed down. The recipe's composite applies it
        // (`original + mask × strength × pass`), and masking here as well would apply it twice and
        // darken the subject edge on every re-render. Same reason the mock ignores it.
        let request = TiledControlNetPass.Request(prompt: Self.conditioningPrompt,
                                                  negativePrompt: Self.negativePrompt,
                                                  seed: chosenSeed,
                                                  settings: settings)

        // Off the main actor: this is minutes of Core ML on a phone.
        let image = try await Task.detached(priority: .userInitiated) { () -> CGImage in
            try pass.run(photo,
                         request: request,
                         conditioning: .theTileItself,
                         preview: { partial in
                             // Published on **every tile**. The comparison split is the resting
                             // state of this app, so a pass that composed once at the end would show
                             // two identical pictures for the whole wait — which reads as broken,
                             // not as slow.
                             guard let partial else { return }
                             progress(EnhanceProgress(step: 0,
                                                      totalSteps: plan.totalSteps,
                                                      intermediate: partial))
                         },
                         steps: { reported in
                             progress(EnhanceProgress(step: reported.step,
                                                      totalSteps: reported.totalSteps))
                         },
                         isCancelled: { cancelled.isSet })
        }.value

        if cancelled.isSet || Task.isCancelled { throw EnhanceError.cancelled }

        return EnhancedPhoto(image: image,
                             // What actually ran, not what was asked for.
                             renderedStrength: builtFor.value,
                             seed: chosenSeed,
                             steps: plan.totalSteps)
    }

    /// What the pass will be handed after its own downscale, so the tile count is computed against
    /// the real geometry rather than the master's.
    ///
    /// Aspect-preserving. Squaring a photo silently is the kind of bug nobody reports, because they
    /// assume the model did it.
    static func workingSize(width: Int, height: Int, side: Int) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > side else { return (width, height) }
        let scale = Double(side) / Double(longest)
        return (max(1, Int((Double(width) * scale).rounded())),
                max(1, Int((Double(height) * scale).rounded())))
    }
}

/// A flag read between units of work.
///
/// The pass spends each step inside a non-cancellable Core ML prediction, so `Task.cancel()` alone
/// cannot stop it — `isCancelled:` is checked between steps and this is what it reads.
final class EnhanceCancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
    func reset() { lock.lock(); value = false; lock.unlock() }
}
