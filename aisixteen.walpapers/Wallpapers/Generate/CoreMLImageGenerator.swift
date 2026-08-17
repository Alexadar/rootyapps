import Foundation
import CoreML
import Synchronization
// `@preconcurrency` because Apple's package predates strict concurrency and marks neither
// `StableDiffusionPipeline` nor its `Configuration` as `Sendable`. Crossing them into the detached
// thread below is nonetheless safe here, and not by assumption: the pipeline is created inside this
// class, is never handed out, and only one generation runs at a time — `CreateModel` cancels the
// previous job before starting another. Without this the file emits six warnings that would train
// the eye to ignore exactly the diagnostics that matter.
@preconcurrency import DiffusionKit
import GenerationKit
import TaskKit

/// The real thing: Stable Diffusion 1.5, converted to Core ML, running on device.
///
/// It conforms to the same `ImageGenerator` the mock does, and **no view changed to accommodate
/// it.** That was the point of building the seam first — this file is the whole integration.
///
/// Three stages, presented to the caller as one job:
///
/// 1. **Generate** — 512 × 512 diffusion, LoRA-fused for dynamic range.
/// 2. **Upscale** — ESRGAN ×4 to 2048 × 2048, tiled (`Upscaler`). This is the master, saved as-is.
/// 3. *(Enhance — ControlNet tile refine at 1024², nine tiles; a separate deliberate action.)*
///
/// **Square, and deliberately so** — SD 1.5 was trained at 512², and asking the converted graph for
/// a portrait shape costs coherence. Core ML graphs are fixed-shape, so `aspect` is never handed to
/// the unet at all: it generates one size and one only. What `aspect` controls is the final fit,
/// which happens at the moment a screen is named, in `WallpaperFitting`.
///
/// The honest cost is recorded in `PipelineSizeChecks`: a 2048² master cropped to a 1208 × 2624
/// phone panel keeps 943 px of width, so setting it enlarges by ~1.28×. At a 1024 master that would
/// be 2.56×, which is why the master is 2048.
///
/// This comment previously described a 512 × 896 / 2048 × 3584 portrait pipeline, left over from
/// before the square decision. It was wrong for long enough to mislead a planning pass into
/// designing a twelve-tile Enhance. Keep it true to the converted graph — the unet's latent sample
/// shape is `[2, 4, 64, 64]`, and 64 × 8 = 512.
final class CoreMLImageGenerator: ImageGenerator {

    private let resourcesURL: URL
    private let plan: GenerationPlan
    private let cancelled = Mutex<Bool>(false)
    /// Stage 2. Optional: without it the picture is still correct, just smaller.
    private let upscaler: Upscaler?
    /// Loading the pipeline reads ~850 MB and compiles nothing (the models arrive precompiled), but
    /// it is still seconds of work — so it happens once and is reused across generations.
    private let pipeline = Mutex<StableDiffusionPipeline?>(nil)
    /// Serialises loading. **Not the same guard as `pipeline`**, and the difference is the bug this
    /// fixes: `pipeline` is only populated once every component is resident, so two callers that
    /// arrive during the load both see `nil`, both decide to load, and the phone tries to bring two
    /// 618 MB unets into memory at the same time — which is not slow, it is a hang.
    ///
    /// That is exactly what happened: `preload()` starts a load when Create appears, then tapping
    /// Create calls `prepare()` again while the first is still going. The second caller now blocks
    /// here, and finds the finished pipeline waiting when it wakes.
    private let loadLock = NSLock()

    /// Where a generation reads its resume point and writes its checkpoints, if it has a job behind
    /// it. Set by `CreateModel` immediately before `generate`, and cleared after.
    ///
    /// Deliberately not part of `GenerationRequest`: `GenerationKit` is the seam the mock also
    /// implements, and a mock generation is instant and has nothing to resume. Pushing job storage
    /// into the shared protocol would make every implementation carry a concept only this one needs.
    struct Checkpointing: @unchecked Sendable {
        /// Where the interrupted run got to, if this is a resumption.
        var resumeFrom: JobStore.Checkpoint?
        /// Tiles for stage 2, so an enlargement interrupted part-way is not redone.
        var upscaleTiles: JobStore.TileSet?
        /// Called on the generation thread as each checkpoint falls due.
        var write: @Sendable (JobStore.Checkpoint) -> Void
    }

    /// Every fourth step. A checkpoint is ~800 KB; at every step that is 22 MB of writes per
    /// generation to save an average of half a step. Four steps is about four seconds of work lost
    /// in the worst case, against one write every four seconds — which is the trade that made
    /// checkpointing worth having at all.
    static let checkpointInterval = 4

    private let checkpointing = Mutex<Checkpointing?>(nil)

    /// Attaches (or detaches, with `nil`) the job storage for the next generation.
    func useCheckpointing(_ hooks: Checkpointing?) {
        checkpointing.withLock { $0 = hooks }
    }

    init(resourcesURL: URL, plan: GenerationPlan = .standard, upscalerURL: URL? = nil) {
        self.resourcesURL = resourcesURL
        self.plan = plan
        // A missing or unloadable upscaler is not fatal — stage 1 alone produces a real wallpaper,
        // and failing the whole generation because the enlarger is absent would be the wrong trade.
        self.upscaler = (upscalerURL ?? Upscaler.bundledModelURL()).flatMap { try? Upscaler(modelURL: $0) }
    }

    /// Where the model lives today. Once the Background Assets pack ships this becomes
    /// `AssetPackManager.shared.url(for:)`; until then it is a folder in the app bundle.
    static func bundledResourcesURL() -> URL? {
        Bundle.main.url(forResource: "StableDiffusion", withExtension: nil)
    }

    func cancel() { cancelled.withLock { $0 = true } }

    /// Release the models. Called before Enhance, which builds its own pipeline.
    ///
    /// Without this the app holds ControlledUnet + TextEncoder + VAEDecoder while `TileRefiner`
    /// loads ControlledUnet **again** plus ControlNet and VAEEncoder — roughly 1.5 GB of duplicate
    /// weights, which is what crashed Enhance. Reloading afterwards is cheap now that the Neural
    /// Engine compile is cached; holding two copies is not.
    func unload() {
        loadLock.lock()
        defer { loadLock.unlock() }
        pipeline.withLock { existing in
            existing?.unloadResources()
            existing = nil
        }
    }

    var isReady: Bool { pipeline.withLock { $0 != nil } }

    // MARK: The parts

    /// Where the unet actually is. The shipped bundle contains only `ControlledUnet` — one unet
    /// serving both text-to-image and tile refine, proven bit-identical with zero residuals.
    private static func unetURL(in resourcesURL: URL) -> URL {
        let plain = resourcesURL.appending(path: "Unet.mlmodelc")
        return FileManager.default.fileExists(atPath: plain.path)
            ? plain : resourcesURL.appending(path: "ControlledUnet.mlmodelc")
    }

    /// Every graph the Neural Engine has to compile, **ordered by what a generation needs**.
    ///
    /// Not ordered by size. If the user taps Create at part three, the tuner stands down with
    /// everything text-to-image wants already compiled and only the Enhance-only graphs still
    /// owing — so the interruption costs them nothing. The ControlNet is last for exactly that
    /// reason: it is the only part no generation touches, and it still compiles here so the first
    /// Enhance never pays for it in the foreground.
    ///
    /// The single source of truth for the names the waking capsule shows. A second list would
    /// drift into a different vocabulary for the same files.
    static func parts(at resourcesURL: URL, upscalerURL: URL?) -> [ModelPart] {
        var found: [ModelPart] = [
            ModelPart(id: "textEncoder", name: "Text encoder",
                      bytes: Int64(size(of: resourcesURL.appending(path: "TextEncoder.mlmodelc")))),
            ModelPart(id: "unet", name: "Image model",
                      bytes: Int64(size(of: unetURL(in: resourcesURL)))),
            ModelPart(id: "decoder", name: "Image decoder",
                      bytes: Int64(size(of: resourcesURL.appending(path: "VAEDecoder.mlmodelc")))),
        ]
        if let upscalerURL {
            found.append(ModelPart(id: "upscaler", name: "Enlarger",
                                   bytes: Int64(size(of: upscalerURL))))
        }
        found.append(ModelPart(id: "encoder", name: "Image encoder",
                               bytes: Int64(size(of: resourcesURL.appending(path: "VAEEncoder.mlmodelc")))))
        if let controlNet = controlNetURL(in: resourcesURL) {
            found.append(ModelPart(id: "controlNet", name: "Detail model",
                                   bytes: Int64(size(of: controlNet))))
        }
        return found.filter { $0.bytes > 0 }
    }

    private static func controlNetURL(in resourcesURL: URL) -> URL? {
        let directory = resourcesURL.appending(path: "controlnet")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.first { $0.hasSuffix(".mlmodelc") }.map { directory.appending(path: $0) }
    }

    var tunableParts: [ModelPart] {
        Self.parts(at: resourcesURL, upscalerURL: Upscaler.bundledModelURL())
    }

    /// Force the Neural Engine compile for each part in turn, holding nothing afterwards.
    ///
    /// ### The lock is taken per part, not for the pass
    ///
    /// Held across all six this would be a minutes-long lock, and a real `prepare()` arriving behind
    /// it would block with nothing to report — the 15 % stall this lock's own note describes, moved
    /// up a level. Per part, a real load waits at most one component.
    ///
    /// ### It yields only for the user
    ///
    /// `shouldStandDown` is the runner's cancel flag and nothing else. An earlier version also stood
    /// down on thermal state and Low Power Mode, which is why a pass once stopped after one part and
    /// never resumed: the phone was warm, every launch stood down immediately, and the screen sat at
    /// "1 of 6" for ever with no way to tell why. If this work is too heavy to run it is too heavy
    /// to promise, so it runs.
    func tune(skipping done: Set<String>,
              shouldStandDown: @escaping @Sendable () -> Bool,
              reporting: @escaping @Sendable (TuningEvent) -> Void) async {
        let parts = tunableParts
        let total = parts.count
        for (offset, part) in parts.enumerated() where !done.contains(part.id) {
            if shouldStandDown() {
                reporting(.stoodDown(after: offset, of: total))
                return
            }
            reporting(.began(part: part, index: offset + 1, of: total))
            let started = Date()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                Thread.detachNewThread { [self] in
                    loadLock.lock()
                    defer { loadLock.unlock(); continuation.resume() }
                    guard pipeline.withLock({ $0 }) == nil else { return }
                    autoreleasepool { compile(part) }
                }
            }
            reporting(.finished(part: part, index: offset + 1, of: total,
                                seconds: Date().timeIntervalSince(started)))
        }
    }

    /// Loads one part far enough to force its compile, then lets it go.
    private func compile(_ part: ModelPart) {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        switch part.id {
        case "textEncoder":
            guard let tokenizer = try? BPETokenizer(
                mergesAt: resourcesURL.appending(path: "merges.txt"),
                vocabularyAt: resourcesURL.appending(path: "vocab.json")) else { return }
            try? TextEncoder(tokenizer: tokenizer,
                             modelAt: resourcesURL.appending(path: "TextEncoder.mlmodelc"),
                             configuration: configuration).prewarmResources()
        case "unet":
            try? Unet(modelAt: Self.unetURL(in: resourcesURL),
                      configuration: configuration).prewarmResources()
        case "decoder":
            try? Decoder(modelAt: resourcesURL.appending(path: "VAEDecoder.mlmodelc"),
                         configuration: configuration).prewarmResources()
        case "encoder":
            try? Encoder(modelAt: resourcesURL.appending(path: "VAEEncoder.mlmodelc"),
                         configuration: configuration).prewarmResources()
        case "controlNet":
            guard let url = Self.controlNetURL(in: resourcesURL) else { return }
            try? ControlNet(modelAt: [url], configuration: configuration).prewarmResources()
        case "upscaler":
            // Not `ResourceManaging` — a plain MLModel. Constructing it is the compile.
            guard let url = Upscaler.bundledModelURL() else { return }
            _ = try? MLModel(contentsOf: url, configuration: configuration)
        default:
            return
        }
    }

    // Nothing warms on launch beyond this pass. The model loads when the user asks for a picture, and
    // `prepare(reporting:)` names each component as it lands so the wait is legible.
    //
    // A launch-time compile pass lived here and was removed: it made a freshly installed app start
    // grinding through 1.1 GB of Neural Engine compiles before the user had touched anything, and
    // it needed a marker file, a checklist, a chip and a stand-down policy to explain itself. All of
    // that was scaffolding around work nobody had asked for.

    /// Reads the model into memory. Seconds on a phone — the whole reason `prepare()` is on the
    /// protocol. Called speculatively as soon as the user touches the prompt field, so the cost is
    /// usually paid while they are still typing.
    func prepare(reporting: @escaping @Sendable (PreparationProgress) -> Void) async throws {
        guard !isReady else {
            return reporting(PreparationProgress(fraction: 1, part: nil, index: 0, total: 0))
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Its own thread, not the cooperative pool: this blocks for tens of seconds reading
            // hundreds of megabytes, and it must not hold a pool thread hostage while it does.
            Thread.detachNewThread { [self] in
                do {
                    _ = try loadPipeline(progress: reporting)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func generate(_ request: GenerationRequest,
                  progress: @escaping @Sendable (GenerationProgress) -> Void) async throws -> GeneratedImage {
        let prompt = request.prompt
        let seed = request.seed

        cancelled.withLock { $0 = false }
        let chosenSeed = seed ?? UInt32.randomSeed()
        let steps = max(1, request.steps)

        // Normally a no-op: `prepare()` has already run while the user was typing.
        let pipeline = try loadPipeline()
        if cancelled.withLock({ $0 }) || Task.isCancelled { throw GenerationError.cancelled }

        var configuration = StableDiffusionPipeline.Configuration(prompt: prompt)
        configuration.stepCount = steps
        configuration.seed = chosenSeed
        configuration.guidanceScale = request.guidanceScale
        // CLIP truncates at 77 tokens without saying so, which is why the app warns before this
        // point rather than here — by now the tail is already gone.
        configuration.negativePrompt = request.negativePrompt
        configuration.disableSafety = true          // handled by our own classifier, not SD's
        configuration.schedulerType = .dpmSolverMultistepScheduler

        let hooks = checkpointing.withLock { $0 }
        // A checkpoint from a step that no longer exists is not resumable — the user changed the
        // step count between the interruption and now. `describesSameWork` already refuses that
        // case; this is the second reading of the same rule, at the point where getting it wrong
        // would index off the end of the schedule.
        if let resume = hooks?.resumeFrom, resume.step > 0, resume.step < steps {
            configuration.resumePoint = ResumePoint(step: resume.step,
                                                    latents: resume.latents,
                                                    modelOutputs: resume.modelOutputs,
                                                    lowerOrderStepped: resume.lowerOrderStepped)
        }

        // The pipeline is synchronous and CPU/ANE-bound for tens of seconds. Running it on the
        // cooperative pool would occupy a thread the whole time, so it gets its own.
        let images = try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread { [weak self] in
                do {
                    let produced = try pipeline.generateImages(configuration: configuration) { state in
                        guard let self else { return false }

                        // `step` counts completed steps; the handler fires before the first one.
                        let step = max(1, state.step)
                        var preview: PreviewImage?
                        // The pipeline decodes a preview only when asked, and decoding is a full
                        // VAE pass — cheap next to a step, but not free. The plan's cadence keeps
                        // it to every other step, which is what the UI was designed against.
                        if self.plan.emitsPreview(atStep: step),
                           let cgImage = state.currentImages.compactMap({ $0 }).first,
                           let bitmap = Self.rgbaBytes(from: cgImage) {
                            preview = PreviewImage(
                                pixels: bitmap,
                                size: AspectRatio(width: cgImage.width, height: cgImage.height))
                        }
                        progress(GenerationProgress(step: step, totalSteps: steps, preview: preview))

                        // Written from the generation thread, synchronously, before the next step
                        // starts. Handing it to another queue would mean the process can die with
                        // the checkpoint still in flight — which is the one moment it exists for.
                        if let hooks, let state = state.resumeState,
                           state.completedSteps % Self.checkpointInterval == 0 {
                            hooks.write(JobStore.Checkpoint(
                                step: state.completedSteps,
                                lowerOrderStepped: state.lowerOrderStepped,
                                latents: state.latents,
                                modelOutputs: state.modelOutputs))
                        }

                        // Returning false stops the pipeline. This is the flag `cancel()` sets, and
                        // it is why `ImageGenerator` has an explicit `cancel()` at all: the
                        // generation loop is inside a synchronous call that Task cancellation
                        // cannot reach.
                        return !self.cancelled.withLock { $0 }
                    }
                    continuation.resume(returning: produced)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        if cancelled.withLock({ $0 }) || Task.isCancelled { throw GenerationError.cancelled }

        guard let cgImage = images.compactMap({ $0 }).first else {
            // The pipeline returns nils when it was stopped, and also when the safety checker
            // rejected an image — but safety is disabled here, so this is a stop.
            throw GenerationError.cancelled
        }

        // ── Stage 2 ─────────────────────────────────────────────────────────────────────────
        // 4× with ESRGAN before fitting to the screen, so the wallpaper is sharp at full size
        // rather than a 512-wide picture stretched across it.
        //
        // Reported in **tiles, as its own stage**, not as further diffusion steps. Adding the nine
        // tiles onto the step counter made a 28-step generation announce "step 37 of 37", which
        // contradicts the number the user set and reads as the job having overrun — most visibly on
        // a resumed run, where an inflated total is the first thing anyone would suspect.
        var enlarged = cgImage
        if let upscaler, request.upscale {
            enlarged = (try? upscaler.upscale(cgImage, tiles: hooks?.upscaleTiles) { done, total in
                progress(GenerationProgress(step: done, totalSteps: total,
                                            preview: nil, stage: .enlarging))
            }) ?? cgImage
        }

        if cancelled.withLock({ $0 }) || Task.isCancelled { throw GenerationError.cancelled }

        // **No crop here.** What is returned — and what the library stores — is the full master.
        // The fit to a particular screen happens at the moment a screen is named, in
        // `WallpaperFitting`. Cropping now would be irreversible, would leave Enhance refining a
        // frame whose edges are already gone, and would pick one device's shape for a picture that
        // may be set on three.
        let master = AspectRatio(width: enlarged.width, height: enlarged.height)
        guard let pixels = Self.rgbaBytes(from: enlarged) else {
            throw GenerationError.failed(reason: "The finished picture couldn't be read back.")
        }
        return GeneratedImage(pixels: pixels,
                              size: master,
                              prompt: prompt,
                              seed: chosenSeed,
                              createdAt: Date())
    }

    // MARK: -

    /// Loads the pipeline **component by component**, so the wait can be reported honestly.
    ///
    /// `StableDiffusionPipeline(resourcesAt:)` + `loadResources()` is one opaque call that takes up
    /// to a minute on a cold phone and offers no hook to observe. Core ML gives no progress inside a
    /// single `MLModel` load either. But the pipeline is **four separate models**, and Apple exposes
    /// each type publicly along with a component-wise initialiser — so they can be loaded in turn
    /// and the fraction reported after each.
    ///
    /// The fraction is **weighted by the models' actual sizes on disk**, not by count. Loading the
    /// unet is 73 % of the work and the text encoder 16 %; treating them as "1 of 4" each would put
    /// the bar at 25 % for the first two seconds and then stall for the next forty. Coarse but real
    /// beats smooth and invented, which is the same rule the download bar follows.
    ///
    /// It is not free-running progress — it moves in four jumps. That is the truth of the operation,
    /// and the design (board `5a`) keeps the breathing arc alongside it precisely because the number
    /// cannot be continuous.
    private func loadPipeline(progress: @escaping @Sendable (PreparationProgress) -> Void = { _ in })
        throws -> StableDiffusionPipeline {
        if let existing = pipeline.withLock({ $0 }) { return existing }

        loadLock.lock()
        defer { loadLock.unlock() }
        // Re-check: whoever held the lock may have finished the whole job while this caller waited.
        if let existing = pipeline.withLock({ $0 }) { return existing }

        let configuration = MLModelConfiguration()
        // The unet was converted with SPLIT_EINSUM_V2, which exists specifically to run on the
        // Neural Engine. Leaving this at `.all` lets Core ML choose the GPU instead, which is both
        // slower for this graph and far heavier on memory — the combination that gets an app
        // jetsammed mid-generation.
        configuration.computeUnits = .cpuAndNeuralEngine

        let textEncoderURL = resourcesURL.appending(path: "TextEncoder.mlmodelc")
        // The shipped bundle contains only `ControlledUnet` — one unet serving both stages.
        let plainUnetURL = resourcesURL.appending(path: "Unet.mlmodelc")
        let unetURL = FileManager.default.fileExists(atPath: plainUnetURL.path)
            ? plainUnetURL : resourcesURL.appending(path: "ControlledUnet.mlmodelc")
        let decoderURL = resourcesURL.appending(path: "VAEDecoder.mlmodelc")
        // No `encoderURL` here on purpose — see the note below on why `encoder` is nil. A URL built
        // for a model that is deliberately never constructed reads, to the next person, as a wiring
        // mistake rather than a decision.

        let tokenizer = try BPETokenizer(mergesAt: resourcesURL.appending(path: "merges.txt"),
                                         vocabularyAt: resourcesURL.appending(path: "vocab.json"))
        let textEncoder = TextEncoder(tokenizer: tokenizer, modelAt: textEncoderURL, configuration: configuration)
        let unet = Unet(modelAt: unetURL, configuration: configuration)
        let decoder = Decoder(modelAt: decoderURL, configuration: configuration)
        // The VAE **encoder** is image → latent, used only by image-to-image — which means stage 3
        // (Enhance), not this path. It is left in the bundle so Enhance can use it, but it is not
        // constructed here: loading it for a text-to-image run costs ~170 MB of resident memory to
        // do nothing, and memory is the constraint that reboots the phone.
        let encoder: Encoder? = nil

        // The three a text-to-image run needs, named from the shared parts table.
        let table = Self.parts(at: resourcesURL, upscalerURL: nil)
        func part(_ id: String, fallback: String) -> ModelPart {
            table.first { $0.id == id } ?? ModelPart(id: id, name: fallback, bytes: 0)
        }
        let stages: [(part: ModelPart, load: () throws -> Void)] = [
            (part("textEncoder", fallback: "Text encoder"), textEncoder.loadResources),
            (part("unet", fallback: "Image model"), unet.loadResources),
            (part("decoder", fallback: "Image decoder"), decoder.loadResources),
        ]

        let total = max(stages.reduce(0.0) { $0 + Double($1.part.bytes) }, 1)
        var done = 0.0
        for (index, stage) in stages.enumerated() {
            if cancelled.withLock({ $0 }) { throw GenerationError.cancelled }
            try stage.load()
            done += Double(stage.part.bytes)
            progress(PreparationProgress(fraction: done / total, part: stage.part,
                                         index: index + 1, total: stages.count))
        }

        let built = StableDiffusionPipeline(textEncoder: textEncoder,
                                            unet: unet,
                                            decoder: decoder,
                                            encoder: encoder,
                                            controlNet: nil,
                                            safetyChecker: nil,
                                            reduceMemory: true)
        pipeline.withLock { $0 = built }
        progress(PreparationProgress(fraction: 1, part: nil, index: stages.count,
                                     total: stages.count))
        return built
    }

    /// Total bytes of a compiled model directory.
    private static func size(of url: URL) -> Double {
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        var bytes = 0.0
        for case let file as URL in files {
            bytes += Double((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return bytes
    }

    /// 8-bit RGBA, row-major, no padding — the buffer shape `GenerationKit` transports.
    private static func rgbaBytes(from image: CGImage) -> Data? {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes,
                                      width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Data(bytes)
    }

}
