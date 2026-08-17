import SwiftUI
import CoreGraphics
import Observation
import RecipeKit
import EnhanceKit
import EditsKit

/// Where the pass is. Drives the capsule morph and nothing else.
enum JobPhase: Equatable {
    case idle
    case running(step: Int, totalSteps: Int)
    case complete
    case failed(EnhanceError)
    /// Transient. Cancel plays the morph in reverse and lands back on `.idle`; the separate case
    /// exists so the reverse animation has something to animate *from*.
    case cancelling

    var isRunning: Bool {
        if case .running = self { return true }
        return self == .cancelling
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// The stage of the morphing capsule. One identity, four shapes (`1b` → `1c` → `1d`).
enum MorphStage: Equatable {
    case enhance
    case progress
    case save
    case failure
}

/// One photo being edited: its pixels, its recipe, its masks, and the job.
///
/// ### What this type guarantees
///
/// 1. **The original is never mutated.** `original` is a `let`. Nothing here writes to
///    `record.originalURL`; the library has no method that would.
/// 2. **Strength 0 shows the original itself.** `displayImage` goes through `PhotoCompositor`,
///    which returns the very `CGImage` it was handed for the `.original` case.
/// 3. **Cancelling changes nothing.** A cancelled pass leaves `recipe` exactly as it was, which is
///    why `pendingStrength` exists — the dial the user is dragging is not committed to the recipe
///    until a pass succeeds.
@MainActor
@Observable
final class EditModel {

    // MARK: The photo

    /// ⚠️ `let`. The decoded original, orientation already baked in. Every other image in this type
    /// is derived from it, and it is the thing that must come back untouched.
    let original: CGImage
    let record: EditRecord

    private(set) var recipe: EditRecipe
    private(set) var pass: CGImage?
    private(set) var masks: [MaskSource: CGImage] = [:]

    /// The picture as it stands mid-pass, published on every tile.
    ///
    /// ⚠️ Not cosmetic. The comparison split is this app's resting state, so a pass that only
    /// composed at the end would show two identical pictures under the handle for the whole wait —
    /// which reads as broken rather than as slow. Cleared the moment the pass ends, in every
    /// direction, so a cancelled run leaves nothing behind.
    private(set) var preview: CGImage?

    // MARK: Controls

    /// ⚠️ Availability is updated **synchronously** here, before any async work starts.
    ///
    /// Deferring it to the `Task` leaves a window — short, but a whole frame — in which a freshly
    /// picked scope still reports the previous one's state. In that window Brush with nothing
    /// painted says "ready" and the Enhance capsule is live, which is precisely the mistake the
    /// availability type exists to prevent.
    var scope: Scope = .whole {
        didSet {
            guard scope != oldValue else { return }
            maskAvailability = immediateAvailability(for: scope)
            if maskAvailability == .working {
                Task { await prepareMask(for: scope) }
            }
        }
    }

    private func immediateAvailability(for scope: Scope) -> MaskAvailability {
        switch scope {
        case .whole:
            return .ready
        case .brush:
            return brushCoverage.isEmpty ? .nothingPainted : .ready
        case .subject, .background:
            return masks[.segmentation] == nil ? .working : .ready
        }
    }

    /// The dial. Committed to the recipe only when a pass succeeds, or immediately when the user is
    /// backing off a pass that already exists.
    var strength: Strength = .default {
        didSet { commitStrengthIfBackingOff() }
    }

    var comparison = Comparison()
    var phase: JobPhase = .idle
    private(set) var maskAvailability: MaskAvailability = .ready
    private(set) var brushCoverage: BrushMask

    // MARK: Collaborators

    /// Builds the enhancer for one pass.
    ///
    /// ⚠️ Per-pass, not per-model. The real pipeline needs the strength **and** the photo's shape
    /// before it starts — the denoise fraction fixes how many steps the scheduler runs and the
    /// shape fixes how many tiles there are, and together they are the step total the capsule shows
    /// from its first frame. A single long-lived enhancer could not know either.
    typealias EnhancerProvider = @MainActor (Strength, CGImage) -> any PhotoEnhancer

    private var enhancer: any PhotoEnhancer
    private let makeEnhancer: EnhancerProvider
    private let segmenter: any Segmenter
    private let library: EditLibrary
    private var job: Task<Void, Never>?

    init(original: CGImage,
         record: EditRecord,
         library: EditLibrary,
         enhancer: @escaping EnhancerProvider = EnhancerFactory.make,
         segmenter: any Segmenter = VisionSegmenter()) {
        self.original = original
        self.record = record
        self.recipe = record.recipe
        self.library = library
        self.makeEnhancer = enhancer
        self.enhancer = enhancer(record.recipe.edit(for: .whole)?.strength ?? .default, original)
        self.segmenter = segmenter
        self.brushCoverage = BrushMask(width: original.width, height: original.height)
        self.strength = recipe.edit(for: .whole)?.strength ?? .default
    }

    // MARK: What the screen shows

    /// The enhanced side of the split — or the original itself when nothing contributes.
    var displayImage: CGImage {
        // Mid-pass the enhanced side is whatever the model has produced so far, so the split
        // handle compares something real rather than the original against itself.
        if phase.isRunning, let preview { return preview }
        return PhotoCompositor.render(original: original,
                               pass: pass,
                               composite: recipe.composite(),
                               masks: masks)
    }

    /// True when the enhanced side is byte-identical to the original, so the UI can stop offering a
    /// comparison of a picture with itself.
    var isShowingOriginalOnly: Bool { recipe.composite().isOriginal }

    var morphStage: MorphStage {
        switch phase {
        case .idle:       return recipe.hasVisibleEnhancement ? .save : .enhance
        case .running, .cancelling: return .progress
        case .complete:   return .save
        case .failed:     return .failure
        }
    }

    var stepLabel: String {
        if case .running(let step, let total) = phase {
            return "Enhancing · step \(step) of \(total)"
        }
        return "Enhancing"
    }

    var progressFraction: Double {
        guard case .running(let step, let total) = phase, total > 0 else { return 0 }
        return min(1, max(0, Double(step) / Double(total)))
    }

    /// The veil's blur in points at the current step, before Reduce Motion quantises it.
    var veilBlur: Double {
        guard case .running(let step, _) = phase else { return 0 }
        return enhancer.plan.veilBlur(atStep: step)
    }

    var veilOpacity: Double { enhancer.plan.veilOpacity }

    // MARK: The dial

    /// Backing off a pass is free and immediate; pushing past what was rendered is not committed at
    /// all — it stays a pending request until the user runs the pass again.
    private func commitStrengthIfBackingOff() {
        guard var edit = recipe.edit(for: scope), edit.hasPass else { return }
        guard let rendered = edit.rendered, strength <= rendered else { return }
        edit.strength = strength
        recipe.set(edit)
        Task { await persistRecipe() }
    }

    /// True when the dial has been pushed above what the current scope's pass rendered, so the UI
    /// can offer Enhance again instead of showing a picture that does not match the number.
    var needsRerun: Bool {
        guard let edit = recipe.edit(for: scope), edit.hasPass, let rendered = edit.rendered
        else { return false }
        return strength > rendered
    }

    var canEnhance: Bool {
        guard !phase.isRunning else { return false }
        guard !strength.isZero else { return false }
        return maskAvailability.allowsEnhance
    }

    // MARK: Masks

    func prepareMask(for scope: Scope) async {
        switch scope {
        case .whole, .brush:
            maskAvailability = immediateAvailability(for: scope)
        case .subject, .background:
            if masks[.segmentation] != nil {
                maskAvailability = .ready
                return
            }
            maskAvailability = .working
            let mask = try? await segmenter.subjectMask(for: original)
            guard let mask else {
                maskAvailability = .noSubjectFound
                return
            }
            masks[.segmentation] = mask
            maskAvailability = .ready
            await persistMask(mask, source: .segmentation)
        }
    }

    func paintBrush(at points: [CGPoint], radius: Double, erasing: Bool) {
        brushCoverage.paint(points, radius: radius, erasing: erasing)
        masks[.brush] = brushCoverage.cgImage()
        if scope == .brush {
            maskAvailability = brushCoverage.isEmpty ? .nothingPainted : .ready
        }
    }

    // MARK: The pass

    func enhance() {
        guard canEnhance else { return }
        let requested = strength
        let currentScope = scope
        let mask = MaskRef.forScope(currentScope).flatMap { masks[$0.source] }

        // Rebuilt for this pass, because the step total is a function of this strength and this
        // photo's shape. Assigned before the phase is set so the capsule's first frame already has
        // the real number.
        enhancer = makeEnhancer(requested, original)
        phase = .running(step: 0, totalSteps: enhancer.plan.totalSteps)

        job = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await enhancer.enhance(
                    photo: original,
                    strength: requested.value,
                    mask: mask,
                    seed: recipe.seed
                ) { progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.phase.isRunning else { return }
                        if let intermediate = progress.intermediate {
                            self.preview = intermediate
                        }
                        // A preview-only report carries no step number. Letting it through would
                        // reset the counter to zero every time a tile lands, which looks like the
                        // pass restarting.
                        if progress.step > 0 {
                            self.phase = .running(step: progress.step,
                                                  totalSteps: progress.totalSteps)
                        }
                    }
                }
                await finish(result, scope: currentScope, requested: requested)
            } catch let error as EnhanceError {
                await failed(error)
            } catch {
                await failed(.failed(reason: error.localizedDescription))
            }
        }
    }

    /// Plays the morph in reverse and leaves the photo untouched.
    func cancel() {
        guard phase.isRunning else { return }
        phase = .cancelling
        enhancer.cancel()
        job?.cancel()
    }

    /// Throws the pass away. Always available, always free (`1d`).
    func revert() {
        job?.cancel()
        enhancer.cancel()
        recipe.revertAll()
        pass = nil
        preview = nil
        phase = .idle
        comparison = Comparison()
        Task { await persistRecipe() }
    }

    private func finish(_ result: EnhancedPhoto, scope: Scope, requested: Strength) async {
        preview = nil
        pass = result.image
        recipe.seed = result.seed
        recipe.update(scope) { $0.markRendered(at: Strength(result.renderedStrength)) }
        strength = requested
        phase = .complete
        comparison = Comparison()
        await persistRecipe()
        await persistEnhanced()
    }

    private func failed(_ error: EnhanceError) async {
        preview = nil
        // A cancel is not a failure and must never reach the failure card.
        if error == .cancelled {
            phase = .idle
            return
        }
        phase = .failed(error)
    }

    func dismissFailure() { phase = .idle }

    // MARK: Persistence — never the original

    private func persistRecipe() async {
        let recipe = self.recipe
        let record = self.record
        let library = self.library
        await Task.detached(priority: .utility) {
            try? library.save(recipe: recipe, for: record)
        }.value
    }

    private func persistEnhanced() async {
        guard let image = pass else { return }
        let composite = recipe.composite()
        let masks = self.masks
        let original = self.original
        let record = self.record
        let library = self.library

        await Task.detached(priority: .utility) {
            let rendered = PhotoCompositor.render(original: original,
                                                  pass: image,
                                                  composite: composite,
                                                  masks: masks)
            guard let data = ImageCoder.encode(rendered) else { return }
            try? library.write(enhanced: data, for: record)
        }.value
    }

    private func persistMask(_ mask: CGImage, source: MaskSource) async {
        let record = self.record
        let library = self.library
        await Task.detached(priority: .utility) {
            guard let data = ImageCoder.encode(mask, as: .png) else { return }
            try? library.write(mask: data, source: source, for: record)
        }.value
    }

    // MARK: Export

    /// The bytes the export sheet hands to Photos or the share sheet. Rendering here rather than
    /// reading the saved file means what is exported is exactly what is on screen, including a dial
    /// the user moved a second ago.
    func exportData() -> Data? {
        ImageCoder.encode(displayImage)
    }

    /// The invariant, checkable from the UI layer and asserted by the tests on every exit path.
    func originalIsIntact() -> Bool {
        (try? library.verifyOriginal(record)) != nil && library.originalIsSealed(record)
    }
}
