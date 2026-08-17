import Foundation
import SwiftUI
import GenerationKit
import LibraryKit
import PromptKit
import TaskKit

/// The Create screen's state machine.
///
/// The axis the test suite cares most about is cancellation, because it is the one most likely to be
/// quietly broken: a cancelled job must leave the prompt intact, write nothing to the library, and
/// return the interface to exactly where it was — from any step, including the last one.
@MainActor
@Observable
final class CreateModel {

    /// What the job is doing. Deliberately carries no images: `PlatformImage` is not `Equatable`,
    /// and an `Equatable` phase is what lets SwiftUI drive the morph off a single `value:`.
    enum Phase: Equatable {
        case idle
        case typed
        /// The model is being read into memory. A separate state because it is *not* step zero of
        /// a run: there are no steps yet, and showing "Step 0 of 28" while several hundred megabytes
        /// load is a progress indicator that does not move — the one thing the design forbids.
        case preparing
        case running(step: Int, totalSteps: Int)
        /// Stage 2. A separate case because it counts **tiles**, not steps — folding it into
        /// `running` is what made a 28-step generation announce "step 37 of 37".
        case enlarging(tile: Int, totalTiles: Int)
        case done(id: String)
        /// The prompt field, reopened over a finished picture (board `5b`). A distinct state from
        /// `.typed` because the picture is still on screen behind a scrim, and the primary button
        /// reads *Regenerate* rather than *Create* — the user is iterating on this image, not
        /// starting from nothing.
        case editing(id: String)
        case failed(reason: String)
    }

    /// The four appearances the one glass object takes. Coarser than `Phase` on purpose: the morph
    /// must not re-run its spring on every one of twenty-eight steps, only when the object actually
    /// becomes a different thing.
    enum MorphStage: Equatable {
        case button
        /// The model is loading. Same capsule, no fill — there is nothing honest to count yet.
        case waking
        case progress
        case result
        case failure
    }

    private(set) var phase: Phase = .idle
    var prompt: String = "" {
        didSet {
            guard !isRunning else { return }
            // While editing over a picture the phase must stay `.editing` — the picture is still
            // on screen and the button still says Regenerate. Only the text changed.
            if case .editing = phase { return }
            // Editing the prompt straight from a finished picture means the user has moved on from
            // it. Holding `.done` here was what made the result a dead end.
            if case .done = phase {
                finished = nil
                finishedRecord = nil
                preview = nil
            }
            phase = PromptRules.isUsable(prompt) ? .typed : .idle
        }
    }

    /// The latest decoded latent. Separate from `phase` so a new picture does not restart the morph.
    private(set) var preview: PlatformImage?
    private(set) var finished: PlatformImage?
    private(set) var finishedRecord: WallpaperRecord?
    /// Points of blur over the forming picture, 26 → 0.
    private(set) var veilBlur: Double = 0
    /// "Stopped — your prompt is kept". Fades after two seconds.
    private(set) var toast: String?

    var aspect: AspectRatio = .phone
    /// Advanced controls. Defaults work; a user need never open them.
    let settings = AdvancedSettings()

    private let generator: any ImageGenerator
    private let plan: GenerationPlan
    /// The single owner of model work. Generating and enhancing both go through it, which is what
    /// makes "no Create while enhancing" a property of the design rather than a rule to remember.
    let runner: JobRunner
    private var preloadTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var wakingTimer: Task<Void, Never>?
    private var surpriseRNG = SeededRandomNumberGenerator(seed: UInt32.randomSeed())
    private let surprise = SurpriseMe()

    init(generator: any ImageGenerator = GeneratorFactory.make(), plan: GenerationPlan = .standard) {
        self.generator = generator
        self.plan = plan
        // Closures, not the generator itself: the runner owns *when* model work happens, not what
        // it is, and handing it a generator was the only thing tying it to this app.
        self.runner = JobRunner(releaseModels: { generator.unload() },
                                cancelWork: { generator.cancel() })
    }

    // MARK: Derived

    var isRunning: Bool {
        switch phase {
        case .running, .preparing, .enlarging: return true
        default: return false
        }
    }

    /// True once waking has run long enough to deserve an explanation (board `5a`: ~3 s).
    private(set) var wakingIsSlow = false

    /// How much of the model is resident, 0–1. Real: it is bytes of model loaded, weighted by the
    /// components' sizes on disk. It moves in four jumps rather than continuously, which is why the
    /// breathing arc stays — the number tells the user the wait is finite, the arc carries the
    /// seconds in between.
    private(set) var wakingFraction: Double = 0

    /// The component that most recently became resident — "Text encoder", "Image model".
    ///
    /// `nil` until the first one lands, and that is load-bearing: before then there is no percentage
    /// to show, and "0%" is the stopped counter the brief bans. Named from the same parts table the
    /// generator loads them from, so the label and the file cannot drift apart.
    private(set) var wakingPart: String?

    /// One sentence per component, rather than one shape for two minutes.
    ///
    /// `wakingFraction` has always been honest — bytes loaded, weighted by size on disk, moving in
    /// four jumps. The design stops hiding the jumps: each landing part names itself, and the arc
    /// carries the seconds in between. A user who sees a *sequence* reads a long wait as progress; a
    /// single unchanging arc reads as a hang, however truthful the number behind it.
    private var wakingText: String {
        guard let wakingPart else { return "Waking the model…" }
        return "\(wakingPart) ready · \(Int(wakingFraction * 100))%"
    }

    /// Whether the prompt field is open over a finished picture.
    var isEditingOverImage: Bool { if case .editing = phase { return true }; return false }

    /// The primary button's verb. *Regenerate* while iterating on a picture that is still on screen.
    var primaryVerb: String { isEditingOverImage ? "Regenerate" : "Create" }

    /// Includes the runner, so the Create button is disabled while an Enhance is refining tiles.
    /// Starting a generation then would put two pipelines in memory at once — the allocation that
    /// crashed this app and rebooted the test phone.
    var canStart: Bool { PromptRules.isUsable(prompt) && !isRunning && runner.canStart(.generate) }

    var morphStage: MorphStage {
        switch phase {
        case .idle, .typed:
            return .button
        case .preparing:
            return .waking
        case .running, .enlarging:
            return .progress
        case .done, .editing:
            return .result
        case .failed:
            return .failure
        }
    }

    var stepText: String {
        switch phase {
        // Named, not numbered. There is no honest number to show while the model loads, so it says
        // what is happening instead of inventing a fraction.
        case .preparing:
            // A percentage only once there is one. Before the first component finishes there is
            // nothing to report, and "0%" would be the stopped counter all over again.
            return wakingText
        // `max(1, …)`: the generator reports the step that just *completed*, so it is 0 until the
        // first one lands. "Step 0 of 28" is a counter that does not move — the exact thing board
        // 5a exists to eliminate. Naming the step being worked on is both honest and what the
        // board's transition diagram shows: "Step 1 of 28" with the fill still at zero.
        case .running(let step, let total): return "Step \(max(1, step)) of \(total)"
        case .enlarging(let tile, let total): return "Enlarging… tile \(tile) of \(total)"
        default: return ""
        }
    }

    /// How full the bar is, across **both** stages.
    ///
    /// The text names its own unit — "Step 9 of 28", then "Enlarging… tile 3 of 9" — but the bar has
    /// to stay one continuous thing. Reading each stage's own fraction would run it to 100 %, then
    /// drop it to 11 % when enlargement began, which reads as the job starting over. That is the
    /// same failure as the counter that announced "step 37 of 37"; only the symptom moved.
    ///
    /// Split by measured time, not by unit count: 25.4 s of diffusion against 5.4 s of enlargement
    /// on this hardware. Weighting them equally would stall the bar at four-fifths for a stage that
    /// takes a fifth of the wait.
    static let diffusionShareOfTheBar = 0.82

    /// How much of the bar stage 1 gets **for this run**.
    ///
    /// With enlargement switched off in Advanced, diffusion *is* the whole job, and reserving the
    /// last fifth for a stage that will never run would leave the bar stuck at 82 % on a finished
    /// wallpaper. Reading the setting rather than assuming is the difference between a bar that goes
    /// backwards and one that never arrives — both were shipped, one after the other.
    private var diffusionShare: Double {
        settings.upscaleEnabled ? Self.diffusionShareOfTheBar : 1.0
    }

    var fraction: Double {
        switch phase {
        case .running(let step, let total):
            guard total > 0 else { return 0 }
            let within = min(1, max(0, Double(step) / Double(total)))
            return within * diffusionShare
        case .enlarging(let tile, let total):
            // Enlargement is under way, so it is running whatever the setting now says — a user who
            // toggles it mid-job must not make the bar jump.
            let share = Self.diffusionShareOfTheBar
            guard total > 0 else { return share }
            let within = min(1, max(0, Double(tile) / Double(total)))
            return share + within * (1 - share)
        default:
            return 0
        }
    }

    // MARK: Actions

    /// Fills the field visibly. **It never generates.**
    ///
    /// A user who does not know what to type learns what a good prompt looks like by reading one and
    /// then editing a word of it. A button that silently produced a picture would hand them a result
    /// and no vocabulary, and the second tap would be as much of a mystery as the first.
    func surpriseMe() {
        // Fills the negative too: someone learning to prompt from this control should see both
        // halves of what makes a good result, not only the half in the visible box.
        let pair = surprise.suggestionPair(using: &surpriseRNG, avoiding: prompt)
        prompt = pair.prompt
        settings.negativePrompt = pair.negative
    }

    /// Starts loading the model without generating anything.
    ///
    /// **Not called on appear.** Reading 850 MB into memory the moment a screen opens is work the
    /// user never asked for — it costs battery and memory whether or not they intend to generate
    /// anything, and someone who opened the app to look at the gallery pays for a model they will
    /// not use. The load happens when Create is pressed.
    ///
    /// Kept because it is the right hook if that decision is ever revisited, and because the
    /// generator's own serialisation depends on there being one entry point.
    ///
    /// Its progress caption on Create was removed with the decision, not left behind: an
    /// `isPreloading` that could never be true made a screen read as if it reported background
    /// loading it never did. Re-enabling this means restoring that indicator too, or the model
    /// becomes resident behind a screen that looks idle — the thing the caption existed to prevent.
    func preload() {
        guard !generator.isReady, preloadTask == nil else { return }
        preloadTask = Task { [generator] in
            try? await generator.prepare { progress in
                Task { @MainActor [weak self] in self?.absorb(preparation: progress) }
            }
            await MainActor.run { [weak self] in self?.preloadTask = nil }
        }
    }

    /// Why the last Enhance failed, if it did.
    ///
    /// Every step of that path used to be `try?`, so a failure produced no file, no picture and no
    /// explanation — indistinguishable from the feature quietly doing nothing. A long operation
    /// that can fail must say so.
    private(set) var enhanceError: String?

    /// Stage 3 progress: tiles done, tiles total. `nil` when not enhancing.
    private(set) var enhanceProgress: (done: Int, total: Int)?

    var isEnhancing: Bool { enhanceProgress != nil }

    var enhanceText: String {
        guard let p = enhanceProgress else { return "" }
        return "Adding detail… tile \(p.done) of \(p.total)"
    }

    /// Refines a finished wallpaper in place: tile-by-tile img2img with Tile ControlNet.
    ///
    /// Deliberately a separate action rather than part of every generation — measured at ~15 s per
    /// tile, a 2048² master is roughly four minutes, and nobody should spend that before knowing
    /// whether they want the picture.
    func enhance(_ record: WallpaperRecord, library: LibraryModel?) {
        guard runner.canStart(.enhance),
              let resources = CoreMLImageGenerator.bundledResourcesURL(),
              // Not "is there a ControlNet on disk" but "does the installed model declare one".
              // The same question, asked of the model rather than of the filesystem.
              let model = ModelCatalog.installed(at: resources), model.hasControlNet,
              TileRefiner.isAvailable(at: resources) else { return }

        enhanceProgress = (0, 1)
        enhancingRecordID = record.id
        enhanceError = nil
        let refiner = TileRefiner(resourcesURL: resources,
                                  steps: settings.refineSteps,
                                  strength: Float(settings.refineStrength),
                                  negativePrompt: settings.negativePrompt)

        // The job's identity, so an interrupted refinement is picked up rather than restarted.
        // Deterministic in the record: enhancing the same wallpaper twice addresses the same
        // directory, which is the only way a *later launch* can find the tiles this one wrote.
        let grid = TileRefiner.grid(width: TileRefiner.workingSide, height: TileRefiner.workingSide)
        let manifest = JobManifest(
            id: "enhance-\(record.id)",
            kind: .enhance(recordID: record.id),
            prompt: record.prompt,
            negativePrompt: settings.negativePrompt,
            seed: record.seed,
            steps: settings.refineSteps,
            guidanceScale: 5.0,
            aspect: record.aspect,
            strength: settings.refineStrength,
            tile: TileRefiner.tile,
            overlap: TileRefiner.overlap,
            workingSide: TileRefiner.workingSide,
            origins: grid.map { .init(x: $0.x, y: $0.y) },
            // An Enhance runs one subtask and depends on one model. It never diffuses from noise
            // and never enlarges, so recording those would make it unresumable for reasons that
            // have nothing to do with it.
            models: [ModelUse(role: .refine, id: model.id,
                              fingerprint: JobStore.fingerprint(ofModelAt: resources))],
            stage: .refining(tile: 0, of: grid.count),
            startedAt: Date(),
            updatedAt: Date())
        let store = try? JobStore.open(manifest)

        // Letting go of the generation models is the runner's job now, done for every `.enhance`
        // rather than remembered at each call site.
        runner.start(.enhance) { [weak self] cancelledFlag in
            defer { Task { @MainActor [weak self] in
                self?.enhanceProgress = nil
                self?.enhancingRecordID = nil
                self?.enhancePreview = nil
            } }
            func fail(_ reason: String) {
                Task { @MainActor [weak self] in self?.enhanceError = reason }
            }

            guard let data = try? Data(contentsOf: record.imageURL),
                  let platform = Bitmap.platformImage(pngData: data),
                  let full = platform.cgImageForRefinement else {
                return fail("The wallpaper couldn't be read back from your library.")
            }

            // Refine at 1024, not at the master's 2048: four tiles instead of sixteen. The
            // downscale on the way in is supersampling, so the refiner sees a cleaner picture than
            // the master; the enlargement on the way out is by the same upscaler that made the
            // master, so nothing new is being invented by a plain resampler.
            let side = TileRefiner.workingSide
            let source = TileRefiner.resized(full, to: side) ?? full

            let refined: CGImage?
            do {
                refined = try refiner.refine(
                    source,
                    prompt: record.prompt,
                    seed: record.seed,
                    tiles: store?.tiles(.refine),
                    preview: { partial in
                        // Each tile, straight to the screen. Published at the working size rather
                        // than resampled back to the master's 2048² every time — the view scales it
                        // anyway, and nine full-size resamples would cost more than the refinement.
                        guard let partial else { return }
                        let shown = Bitmap.platformImage(cg: partial,
                                                         width: partial.width,
                                                         height: partial.height)
                        Task { @MainActor [weak self] in self?.enhancePreview = shown }
                    },
                    progress: { done, total in
                        // Recorded on disk as well as shown, so the resume card can say how far
                        // this got without re-counting the tile directory.
                        store?.record(stage: .refining(tile: done, of: total))
                        Task { @MainActor [weak self] in self?.enhanceProgress = (done, total) }
                    },
                    isCancelled: { cancelledFlag.isSet })
            } catch is CancellationError {
                return
            } catch let error as GenerationError {
                return fail(error.plainReason)
            } catch {
                return fail("Enhance stopped: \(error.localizedDescription)")
            }

            guard let refined else {
                return fail("Enhance produced no picture.")
            }
            // Plain resample back to the master's size, not another ESRGAN pass. 1024 → 4096 costs
            // a ~200 MB accumulator, and it would immediately be shrunk to 2048 again — paying peak
            // memory for detail that the downscale throws away.
            let sized = TileRefiner.resized(refined, to: full.width) ?? refined
            guard let png = Bitmap.pngData(cg: sized) else {
                return fail("The refined wallpaper couldn't be encoded.")
            }
            // Overwrites the master in place: the enhanced picture *is* the wallpaper now, and the
            // crop to any screen still happens at use time.
            try? png.write(to: record.imageURL, options: .atomic)
            // The work is spent the moment it lands on the master. Leaving the job behind would
            // offer to resume a refinement that has already been applied — and applying it twice
            // would re-refine an already-refined picture.
            store?.discard()
            // Same path, new bytes — the cached thumbnail has to go or the gallery keeps showing
            // the picture from before the refinement.
            await library?.invalidate(record.id)
            // And the finished picture on screen is the pre-enhance one; replace it too.
            if let refreshed = Bitmap.platformImage(pngData: png) {
                await MainActor.run { [weak self] in
                    self?.replaceFinished(with: refreshed, from: record.id)
                }
            }
        }
    }

    /// Which record an Enhance is currently rewriting, or `nil`. Both doors and the Mac's tile veil
    /// ask `enhancingRecordID == record.id` rather than `isEnhancing`, so a refinement started from
    /// the Gallery never veils an unrelated picture on Create.
    private(set) var enhancingRecordID: String?

    /// The refinement as it stands right now, republished after every tile.
    ///
    /// Separate from `finished` on purpose: an Enhance started from the Gallery must not rewrite the
    /// Create screen's picture, and both doors need the same live image. `nil` whenever nothing is
    /// being refined.
    private(set) var enhancePreview: PlatformImage?

    /// Swap the on-screen result for the refined version, without disturbing the phase.
    ///
    /// Gated on the enhanced record actually being the one on screen. While Enhance was reachable
    /// only from the Create result the two were always the same picture; the moment the Gallery door
    /// opens they are not, and an unconditional swap would replace whatever the user was looking at
    /// with something they did not enhance.
    func replaceFinished(with image: PlatformImage, from recordID: String?) {
        guard recordID == nil || recordID == finishedRecord?.id else { return }
        finished = image
    }

    func cancelEnhance() {
        runner.cancel()
    }

    var tunableParts: [ModelPart] { generator.tunableParts }

    /// The one-time Neural Engine compile, part by part, holding no memory afterwards.
    ///
    /// Runs under the job runner, so it yields the instant the user asks for anything and
    /// `canStart` is false while it holds the model — both for free, with no new terms.
    func tune(skipping done: Set<String>,
              reporting: @escaping @MainActor (TuningEvent) -> Void) {
        runner.start(.tune) { [generator] flag in
            await generator.tune(skipping: done,
                                 shouldStandDown: { flag.isSet },
                                 reporting: { event in
                Task { @MainActor in reporting(event) }
            })
        }
    }

    /// **The user physically tapped Create.**
    ///
    /// One entry point for all four Create buttons, so the refusal has a voice. `.disabled()`
    /// swallows the tap, and a disabled button that cannot explain itself reads as broken —
    /// especially when it greys out mid-Enhance for a reason the user cannot see.
    func createTapped(saveTo library: LibraryModel?) {
        if canStart {
            start(saveTo: library)
        } else if !runner.isIdle {
            explainBusy()
        }
        // An unusable prompt says nothing: the empty field is its own explanation.
    }

    /// The one thing a shell may put on the shelf. Deliberately not a general `showToast(_:)` —
    /// that would let any view write any string to a surface with a strict priority order.
    func explainBusy() {
        showToast(EnhanceCopy.oneThingAtATime)
    }

    func start(saveTo library: LibraryModel?, resuming resumed: JobManifest? = nil) {
        guard canStart else { return }
        let text = resumed?.prompt ?? PromptRules.prepared(prompt)
        let aspect = resumed?.aspect ?? aspect
        let negative = resumed?.negativePrompt ?? settings.negativePrompt
        let steps = resumed?.steps ?? settings.generationSteps
        let guidance = resumed.map { Double($0.guidanceScale) } ?? settings.guidanceScale
        let upscaleOn = settings.upscaleEnabled
        // Chosen here rather than inside the generator: the manifest has to record it, and a seed
        // the app never saw could not be written down or resumed into.
        let seed = resumed?.seed ?? UInt32.randomSeed()
        let store = generationStore(prompt: text, negative: negative, seed: seed, steps: steps,
                                    guidance: Float(guidance), aspect: aspect, resuming: resumed)
        preview = nil
        finished = nil
        finishedRecord = nil
        veilBlur = plan.initialVeilBlur
        // Only claim to be on a step once there is one.
        phase = generator.isReady ? .running(step: 0, totalSteps: steps) : .preparing
        wakingIsSlow = false
        wakingPart = nil
        wakingFraction = generator.isReady ? 1 : 0
        if case .preparing = phase { startWakingTimer() }

        runner.start(.generate) { [weak self, generator, plan] _ in
            do {
                // Join the speculative preload if one is already running, rather than asking for a
                // second one. The generator serialises loads anyway, but waiting on the existing
                // task keeps the reported percentage continuous instead of restarting at zero.
                if let existing = await self?.preloadTask { await existing.value }
                try await generator.prepare { progress in
                    Task { @MainActor [weak self] in self?.absorb(preparation: progress) }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.isRunning else { return }
                    self.phase = .running(step: 0, totalSteps: steps)
                }

                let request = GenerationRequest(prompt: text,
                                                negativePrompt: negative,
                                                aspect: aspect,
                                                seed: seed,
                                                steps: steps,
                                                guidanceScale: Float(guidance),
                                                upscale: upscaleOn)
                let image = try await generator.generate(request) { progress in
                    // Recorded on disk as well as shown. Stage 2 is told apart by its total growing
                    // past the diffusion step count — the generator presents both stages as one
                    // continuous counter, which is right for the user and needs undoing here.
                    if progress.stage == .enlarging {
                        store?.record(stage: .upscaling(tile: progress.step, of: progress.totalSteps))
                    }
                    Task { @MainActor [weak self] in
                        self?.absorb(progress, plan: plan)
                    }
                }
                guard !Task.isCancelled else { return }
                // The job is spent once the picture exists. Anything left on disk would be offered
                // on the next launch as work still to do.
                store?.discard()
                await self?.complete(image, library: library)
            } catch let error as GenerationError {
                await self?.finish(with: error)
            } catch {
                await self?.finish(with: .failed(reason: "Something went wrong part-way through."))
            }
        }
    }

    /// Creates (or reopens) the job behind a generation and attaches it to the generator.
    ///
    /// Returns `nil` for the mock generator, which has nothing to checkpoint — a mock run is
    /// instant, and a resume card offering to continue one would be a lie about what happened.
    private func generationStore(prompt: String,
                                 negative: String,
                                 seed: UInt32,
                                 steps: Int,
                                 guidance: Float,
                                 aspect: AspectRatio,
                                 resuming resumed: JobManifest?) -> JobStore? {
        guard let coreML = generator as? CoreMLImageGenerator,
              let generating = ModelCatalog.installedModel(for: .generate) else { return nil }

        // Exactly the subtasks this job will run. Stage 2 only counts if it is actually switched on
        // — a job that never enlarges must not be discarded on the next launch because the upscaler
        // pack changed underneath it.
        var models = [generating]
        if settings.upscaleEnabled, let enlarging = ModelCatalog.installedModel(for: .upscale) {
            models.append(enlarging)
        }

        let manifest = resumed ?? JobManifest(
            kind: .generate,
            prompt: prompt,
            negativePrompt: negative,
            seed: seed,
            steps: steps,
            guidanceScale: guidance,
            aspect: aspect,
            models: models,
            stage: .diffusing(step: 0, of: steps),
            startedAt: Date(),
            updatedAt: Date())

        guard let store = try? JobStore.open(manifest) else { return nil }
        coreML.useCheckpointing(.init(
            // Only when resuming. A fresh job with the same id would otherwise pick up a checkpoint
            // it did not write — and `JobStore.open` has already discarded any that described
            // different work, so what remains here is genuinely this job's.
            resumeFrom: resumed == nil ? nil : store.readCheckpoint(),
            upscaleTiles: store.tiles(.upscale),
            write: { checkpoint in
                store.writeCheckpoint(checkpoint)
                store.record(stage: .diffusing(step: checkpoint.step, of: steps))
            }))
        return store
    }

    /// Stops the run. The prompt survives, nothing is written, and the interface returns to where it
    /// was — the morph plays the same path backwards because it is the same identified object.
    func cancel() {
        runner.cancel()
        wakingTimer?.cancel(); wakingTimer = nil; wakingIsSlow = false
        // The preload is deliberately NOT cancelled: the user stopping a generation does not mean
        // they want the model unloaded, and re-reading 850 MB because they tapped Stop would make
        // the next attempt slower than the first.
        preview = nil
        veilBlur = 0
        phase = PromptRules.isUsable(prompt) ? .typed : .idle
        showToast("Stopped — your prompt is kept")
    }

    /// Same prompt, new seed. The seed is rolled by the generator, so this is genuinely a second
    /// attempt rather than a repeat of the first.
    ///
    /// Refuses out loud, like `createTapped`. This used to fall through to `start`, whose `canStart`
    /// guard returns silently — which was invisible only because the button above it was
    /// `.disabled()`. Removing that without this would have turned one dead control into another.
    func regenerate(saveTo library: LibraryModel?) {
        guard !prompt.isEmpty else { return }
        guard canStart else {
            if !runner.isIdle { explainBusy() }
            return
        }
        phase = .typed
        start(saveTo: library)
    }

    /// Loads a stored wallpaper's prompt back into the field — the gallery's *Use again*.
    func reuse(_ record: WallpaperRecord) {
        prompt = record.prompt
        aspect = record.aspect
        phase = .typed
        finished = nil
        finishedRecord = nil
        preview = nil
    }

    /// Exit ① and ② from a finished picture: back to a clean Create.
    func dismissResult() {
        finished = nil
        finishedRecord = nil
        preview = nil
        phase = PromptRules.isUsable(prompt) ? .typed : .idle
    }

    // MARK: -

    /// Opens the prompt field over the finished picture (board `5b`). The picture stays, behind a
    /// scrim, so the user keeps their reference while changing a word — which is the loop this app
    /// is actually for.
    func tweak() {
        guard case .done(let id) = phase else { return }
        phase = .editing(id: id)
    }

    /// Leaves the editor without regenerating, back to the finished picture.
    func cancelEditing() {
        guard case .editing(let id) = phase else { return }
        phase = .done(id: id)
    }

    /// Waking passes ~3 s: show the one-time-per-session explanation (board `5a`).
    private func startWakingTimer() {
        wakingTimer?.cancel()
        wakingTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, case .preparing = self.phase else { return }
                self.wakingIsSlow = true
            }
        }
    }

    /// Feeds one progress report in, exactly as a generation would. Test seam: the two-stage
    /// reporting is otherwise only reachable by running a real model for half a minute.
    func receiveForTest(_ progress: GenerationProgress) {
        if case .idle = phase { phase = .running(step: 0, totalSteps: progress.totalSteps) }
        if case .typed = phase { phase = .running(step: 0, totalSteps: progress.totalSteps) }
        absorb(progress, plan: plan)
    }

    private func absorb(preparation: PreparationProgress) {
        wakingFraction = preparation.fraction
        if let part = preparation.part { wakingPart = part.name }
    }

    private func absorb(_ progress: GenerationProgress, plan: GenerationPlan) {
        guard isRunning else { return }
        wakingTimer?.cancel(); wakingTimer = nil; wakingIsSlow = false
        switch progress.stage {
        case .generating:
            phase = .running(step: progress.step, totalSteps: progress.totalSteps)
            veilBlur = plan.veilBlur(atStep: progress.step)
        case .enlarging:
            // The picture is already composed by now; the veil is fully lifted and enlarging it
            // must not put it back.
            phase = .enlarging(tile: progress.step, totalTiles: progress.totalSteps)
            veilBlur = 0
        }
        if let latent = progress.preview {
            preview = Bitmap.platformImage(rgba: latent.pixels,
                                           width: latent.size.width,
                                           height: latent.size.height)
        }
    }

    private func complete(_ image: GeneratedImage, library: LibraryModel?) async {
        finished = Bitmap.platformImage(rgba: image.pixels,
                                        width: image.size.width,
                                        height: image.size.height)
        veilBlur = 0
        // Saved immediately and quietly — the design says so, and a dialog asking whether to keep a
        // picture the user just waited twenty seconds for is a question with one answer.
        if let library {
            finishedRecord = try? await library.save(image)
        }
        phase = .done(id: finishedRecord?.id ?? image.prompt)
    }

    private func finish(with error: GenerationError) {
        // A cancelled job is not a failure and must never show the failure card.
        guard error != .cancelled else { return }
        preview = nil
        veilBlur = 0
        phase = .failed(reason: error.plainReason)
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: WPMotion.toastLifetime)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.toast = nil }
        }
    }
}
