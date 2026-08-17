import Foundation
import CoreML
import CoreGraphics
@preconcurrency import DiffusionKit
import ModelKit
import TaskKit

/// Run a ControlNet over a picture, square by square.
///
/// ### One pass, three apps
///
/// Every app built on the `sd15cn` pack does the same thing with a different ControlNet:
///
/// | app | ControlNet | conditioning image | what it is for |
/// |---|---|---|---|
/// | Wallpapers | Tile | the tile itself | adding invented texture at full size |
/// | Studio | Tile | the tile itself | enhancing a photograph |
/// | Architecture | MLSD, Depth | line segments / a depth map | holding a redesign to the room's geometry |
///
/// The differences are the ControlNet name and where the conditioning image comes from. The loop —
/// tiling, overlap, feathering, resumption, publishing partials, memory discipline — is identical,
/// and it is the part that took a fortnight and several device reboots to get right. It lives here
/// so nobody has to learn it twice.
///
/// ### Why the tiles overlap, and why the veil is not literal
///
/// A tile cannot see past its own edge, so butted tiles seam. The last origin on each axis is pulled
/// back to the edge so the final tile is full — the models accept exactly one input size — which
/// means the grid is **not** an even partition: at 1024 the origins are 0, 448, 512. Anything drawing
/// a progress overlay should partition evenly and accept that it is approximate; see the note on
/// `origins(span:tile:step:)`.
///
/// ### Memory, measured
///
/// | | peak | wall time |
/// |---|---|---|
/// | unload every tile, no autorelease pools | 1.43 GB | 372 s |
/// | no `reduceMemory` at all | 2.55 GB | 40 s |
/// | **retain the denoising models, pools in both loops** | **0.46 GB** | **42 s** |
///
/// Both halves matter and neither is optional. `retainsDenoisingModels` stops the 618 MB unet being
/// torn down and re-read between tiles; the pools stop every array Core ML autoreleases living until
/// the whole pass returns. Without the pools a nine-tile pass died at the eighth tile on a phone and
/// took the device down with it.
public struct TiledControlNetPass: Sendable {

    /// What the ControlNet is shown for each tile.
    public enum Conditioning: Sendable {
        /// The tile conditions on itself — Tile ControlNet's whole idea. Keep this square looking
        /// like what it already is, only sharper.
        case theTileItself
        /// A second, pre-computed image the same size as the source, cropped in step with each tile:
        /// a depth map, an MLSD line drawing, a scribble. **Must already be aligned to the source.**
        case aligned(CGImage)
    }

    public struct Settings: Sendable {
        /// The side both converted models were built for. Core ML graphs are fixed-shape.
        public var tile: Int
        /// Pixels of overlap. Larger for generative work than for sharpening, because invented
        /// content disagrees across a boundary far more than a filter does.
        public var overlap: Int
        /// The side the pass runs at. Halving it quarters the tile count; the downscale on the way
        /// in is supersampling, so the pass sees a cleaner picture than the master.
        public var workingSide: Int
        /// How much of each tile is re-diffused. Higher invents objects that were not there and
        /// breaks tile-to-tile agreement.
        public var strength: Float
        /// Nominal steps. At low strength only a fraction actually run — image-to-image skips the
        /// early, noisiest part of the schedule.
        public var steps: Int
        public var guidanceScale: Float
        /// 0 disables the ControlNet's influence entirely, which turns this into plain
        /// image-to-image. Architecture wants this lower than Wallpapers does.
        public var conditioningScale: Float

        public init(tile: Int = 512, overlap: Int = 64, workingSide: Int = 1024,
                    strength: Float = 0.35, steps: Int = 12,
                    guidanceScale: Float = 5.0, conditioningScale: Float = 1.0) {
            self.tile = tile
            self.overlap = overlap
            self.workingSide = workingSide
            self.strength = strength
            self.steps = steps
            self.guidanceScale = guidanceScale
            self.conditioningScale = conditioningScale
        }
    }

    public struct Request: Sendable {
        public var prompt: String
        public var negativePrompt: String
        public var seed: UInt32
        public var settings: Settings

        public init(prompt: String, negativePrompt: String = "", seed: UInt32,
                    settings: Settings = Settings()) {
            self.prompt = prompt
            self.negativePrompt = negativePrompt
            self.seed = seed
            self.settings = settings
        }
    }

    /// How far along, in the two units that exist.
    ///
    /// Tiles are the honest unit of a tiled pass — they are what resumes, what gets written to disk,
    /// and what the picture visibly gains. But an app whose interface counts *steps* should not have
    /// to invent a step number from a tile count, so both are reported and both are real.
    ///
    /// `stepsPerTile` is the count the scheduler will **actually run**, not the nominal `steps`:
    /// image-to-image skips the early part of the schedule, so a nominal 12 at strength 0.35 runs
    /// four. Reporting the nominal number would be a counter that stalls at a third and then jumps.
    public struct Progress: Sendable, Equatable {
        public var tile: Int
        public var totalTiles: Int
        /// 1-based within the current tile.
        public var stepInTile: Int
        public var stepsPerTile: Int

        /// Steps completed across the whole pass, and the total it will run. What an interface that
        /// counts steps should print — every value a real measurement.
        public var step: Int { tile * stepsPerTile + stepInTile }
        public var totalSteps: Int { totalTiles * stepsPerTile }
    }

    /// What a pass *will* run, computable **before it starts** — no model, no pipeline, no disk.
    ///
    /// ### Why this exists
    ///
    /// Two apps independently concluded the total could not be known until the first step landed, and
    /// each designed around it: one planned a countdown with no number until progress arrived, the
    /// other hard-coded 32. Both were reasonable readings of a total that only ever appeared inside a
    /// progress callback — and both were unnecessary. Every input is arithmetic:
    ///
    /// * `totalTiles` is `grid(width:height:tile:overlap:).count`, pure geometry.
    /// * `stepsPerTile` is `DPMSolverMultistepScheduler(stepCount:).calculateTimesteps(strength:)`,
    ///   which is a thousand-element array of `Float`s and no I/O.
    ///
    /// **Cheap, but not free: ~0.7 ms per call in Debug**, nearly all of it building the scheduler's
    /// beta and alpha tables. Fine on a slider drag, fine per pass; not something to call inside a
    /// per-pixel or per-frame loop. It deliberately still asks the real scheduler rather than
    /// reimplementing its arithmetic — the closed form is a two-line expression, and a copy of it here
    /// would be a second source of truth that goes quietly wrong the day Apple changes the first.
    ///
    /// It was hidden rather than absent. So it is exposed here, and `run` uses this same function
    /// rather than computing it again — the number an interface shows before the pass and the number
    /// the loop iterates are one expression, and cannot drift apart.
    ///
    /// ### The one thing it does not know
    ///
    /// A **resumed** pass runs fewer tiles than it plans, because finished ones come back from disk.
    /// `totalTiles` is still the right denominator — the picture needs all of them — but the counter
    /// will start partway up rather than at zero. An interface that treats a non-zero first reading
    /// as a bug will be wrong exactly once per resume.
    ///
    /// - Parameters:
    ///   - width: the source's width **as it will be handed to `run`** — after any downscale to
    ///     `workingSide`, not the master's size. The pass tiles what it is given.
    public struct Plan: Sendable, Equatable {
        public var totalTiles: Int
        /// What the scheduler will actually iterate, not `settings.steps`. At strength 0.18 a nominal
        /// 12 runs **two**; printing 12 gives a counter that sits still and then jumps to done.
        ///
        /// **Zero is reachable and it is fatal** — see `isRunnable`.
        public var stepsPerTile: Int
        public var totalSteps: Int { totalTiles * stepsPerTile }

        /// Whether this pair of settings can run at all.
        ///
        /// The schedule is `steps - Int(steps × strength)` onwards, so when `steps × strength` floors
        /// to zero the start index lands one past the end of the timestep array. This is checkable
        /// with arithmetic and no model, which is the point: a preset table can be asserted valid in
        /// a unit test instead of discovered invalid by a user on the gentlest setting.
        public var isRunnable: Bool { stepsPerTile > 0 }
    }

    /// The lowest strength that runs at least one step for a given step count.
    ///
    /// Deliberately a hair above the exact boundary. `Int(Float(steps) * strength)` is a floating
    /// multiply and `1.0/12.0 * 12` is not reliably `1.0`; landing exactly on the cliff would make
    /// validity depend on the last bit of a `Float`.
    public static func minimumStrength(forSteps steps: Int) -> Float {
        guard steps > 0 else { return 1 }
        return (1.0 / Float(steps)).nextUp
    }

    /// `requested`, raised to the lowest value that actually runs a step.
    ///
    /// ### Why this is not the same as validating a preset table
    ///
    /// A fixed set of presets can be asserted valid case by case. A **continuous control cannot** —
    /// the value set is the whole interval, and a table assertion goes green while a user dragging a
    /// slider reaches the positions nobody enumerated. Measured at `steps: 12`, **84 of 1001**
    /// positions on a 0–1 rail produce an empty schedule. Correcting the four named detents leaves
    /// every one of those 84 reachable.
    ///
    /// So an app mapping any user-movable control onto `strength` should put its curve through this
    /// rather than assert its labels. `run` still *throws* on an unrunnable pair instead of clamping
    /// silently, because a hardcoded 0.05 in source is a programmer error and should be loud; this is
    /// the opt-in for the case where the value legitimately comes from a person's thumb.
    ///
    /// ### The dead zone this exposes but does not fix
    ///
    /// Clamping stops the crash; it does not make the bottom of a rail *do* anything. See
    /// `distinctOutcomes(forSteps:strengthFrom:to:)` for how coarse a given dial really is.
    public static func clamped(strength requested: Float, forSteps steps: Int) -> Float {
        max(requested, minimumStrength(forSteps: steps))
    }

    /// The schedule length for one tile — the whole of what `strength` and `steps` decide together.
    ///
    /// Split out of `plan` because it is the half that has nothing to do with geometry, and both the
    /// resolution question and the runnability question are about this number alone.
    public static func stepsPerTile(strength: Float, steps: Int) -> Int {
        DPMSolverMultistepScheduler(stepCount: steps).calculateTimesteps(strength: strength).count
    }

    /// How many **visibly different results** a strength control can actually produce.
    ///
    /// ### The correction that produced this
    ///
    /// The note here used to say a rail has at most `steps` distinct outcomes. True over the full
    /// 0–1 range, and misleading for any app that caps its range — which an app whose verb is
    /// *enhance* should, since a photograph of someone's child has no business at 0.8.
    ///
    /// Resolution scales with the **fraction of the range you use**, so a cap at 0.5 halves it.
    /// Measured, rail put through `clamped`:
    ///
    /// | steps | full 0–1 | capped 0–0.5 |
    /// |---|---|---|
    /// | 12 | 12 | **6** |
    /// | 24 | 24 | **12** |
    ///
    /// Six results is what a hundred-position slider with four named detents is really offering, and
    /// a third of its travel lands on the same one. That is not a bug to fix here — it is the honest
    /// resolution of the underlying scheduler, and the only lever is `steps`, which costs wall time
    /// roughly in proportion. Whoever owns the dial should know the number before choosing.
    ///
    /// Endpoints are sufficient because `stepsPerTile` is monotonic non-decreasing in strength —
    /// asserted, not assumed, since the whole result rests on it.
    public static func distinctOutcomes(forSteps steps: Int,
                                        strengthFrom lo: Float, to hi: Float) -> Int {
        guard steps > 0, hi >= lo else { return 0 }
        let low = stepsPerTile(strength: clamped(strength: lo, forSteps: steps), steps: steps)
        let high = stepsPerTile(strength: clamped(strength: hi, forSteps: steps), steps: steps)
        return max(high - low + 1, 0)
    }

    public static func plan(for settings: Settings, width: Int, height: Int) -> Plan {
        Plan(totalTiles: grid(width: width, height: height,
                              tile: settings.tile, overlap: settings.overlap).count,
             stepsPerTile: stepsPerTile(strength: settings.strength, steps: settings.steps))
    }

    /// Everything needed to restart an interrupted pass exactly where it stopped.
    ///
    /// ### Two granularities, and the honest difference between them
    ///
    /// **Between tiles** costs nothing and is always on when a `TileSet` is supplied: finished tiles
    /// are written atomically as they complete, so a resumed pass skips them. Worst case you lose
    /// the tile in flight — a few seconds.
    ///
    /// **Within a tile** is this. `latents` plus the scheduler's `modelOutputs` and
    /// `lowerOrderStepped` are the whole of a de-noising loop's state; everything else in
    /// `DPMSolverMultistepScheduler` is `let`, derived from the step count. Measured at ~800 KB for
    /// a 512² tile, which is why a checkpoint every few steps is affordable and one every step is
    /// not.
    ///
    /// Restoring it wrongly does not crash — it resumes onto a slightly different path and produces
    /// a *different picture from the same seed*, which reads as the model being unreliable. The
    /// codec is asserted byte-exact and a split run (straight through vs killed and resumed) is
    /// asserted pixel-identical, because nothing weaker would catch it.
    public struct Checkpoint: Sendable {
        /// The tile that was in flight.
        public var tile: Int
        /// Steps already taken **within** that tile — exactly what the resumed loop skips.
        public var step: Int
        public var lowerOrderStepped: Int
        public var latents: [MLShapedArray<Float32>]
        public var modelOutputs: [MLShapedArray<Float32>]

        public init(tile: Int, step: Int, lowerOrderStepped: Int,
                    latents: [MLShapedArray<Float32>], modelOutputs: [MLShapedArray<Float32>]) {
            self.tile = tile
            self.step = step
            self.lowerOrderStepped = lowerOrderStepped
            self.latents = latents
            self.modelOutputs = modelOutputs
        }

        /// Flat little-endian binary, not `Codable`.
        ///
        /// The payload is a few hundred thousand `Float32`s. JSON would render each as a decimal
        /// string — several times the size, slower, and **lossy at the last bit**, which for
        /// restored diffusion state means the resumed picture differs from the original. Raw floats
        /// round-trip exactly. `JobStore.encode`/`decode` own the format; this only adds the tile.
        public var encoded: Data? {
            guard let body = JobStore.encode(JobStore.Checkpoint(
                step: step, lowerOrderStepped: lowerOrderStepped,
                latents: latents, modelOutputs: modelOutputs)) else { return nil }
            var data = Data()
            withUnsafeBytes(of: UInt32(tile).littleEndian) { data.append(contentsOf: $0) }
            data.append(body)
            return data
        }

        public static func decoded(from data: Data) -> Checkpoint? {
            guard data.count > 4 else { return nil }
            let tile = data.withUnsafeBytes {
                UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self))
            }
            guard let body = JobStore.decode(data.dropFirst(4)) else { return nil }
            return Checkpoint(tile: Int(tile), step: body.step,
                              lowerOrderStepped: body.lowerOrderStepped,
                              latents: body.latents, modelOutputs: body.modelOutputs)
        }
    }

    /// How often a checkpoint is offered, in steps.
    ///
    /// A checkpoint is ~800 KB. Every step would be tens of megabytes of writes per tile to save an
    /// average of half a step; every fourth loses at most four steps. That is the trade that made
    /// checkpointing worth having rather than a cost pretending to be a feature.
    public static let checkpointInterval = 4

    private let resourcesURL: URL
    private let controlNetName: String

    /// - Parameter controlNetName: the compiled model's filename without its extension, as the
    ///   pipeline expects it — e.g. `LllyasvielControlV11F1ESd15Tile`. Use
    ///   `ControlNetCatalog.installed(at:)` to discover what a pack actually carries rather than
    ///   hard-coding a name that a future pack may not include.
    public init(resourcesAt resourcesURL: URL, controlNet controlNetName: String) {
        self.resourcesURL = resourcesURL
        self.controlNetName = controlNetName
    }

    // MARK: The grid

    /// Every tile origin, in working order — left to right, top to bottom.
    ///
    /// Flat rather than nested loops because the index into this list **is** the tile's identity: it
    /// names the file on disk and it goes into the job manifest, so a change to the tiling maths
    /// must never silently reinterpret half-finished work against a different grid.
    public static func grid(width: Int, height: Int, tile: Int, overlap: Int) -> [(x: Int, y: Int)] {
        let step = max(tile - overlap, 1)
        let xs = origins(span: width, tile: tile, step: step)
        let ys = origins(span: height, tile: tile, step: step)
        return ys.flatMap { y in xs.map { (x: $0, y: y) } }
    }

    /// Origins that always yield a full tile — the last is pulled back to the edge rather than
    /// running off it, because the models accept exactly one input size.
    ///
    /// The pull-back is why the grid is not evenly spaced: at span 1024, tile 512, step 448 it gives
    /// 0, 448, 512 — the middle tile overlaps the last by 448 px. Redistributing to 0, 256, 512
    /// would cost the same three tiles and blend better, but it moves pixels, so it is left alone.
    public static func origins(span: Int, tile: Int, step: Int) -> [Int] {
        guard span > tile else { return [0] }
        var result: [Int] = []
        var position = 0
        while position + tile < span {
            result.append(position)
            position += step
        }
        result.append(span - tile)
        return result
    }

    // MARK: The pass

    /// - Parameter tiles: finished tiles on disk, so an interrupted pass resumes rather than
    ///   restarting. Optional; without it the pass is still correct, just not resumable.
    /// - Parameter preview: the picture **as it stands**, republished after every tile. Publishing
    ///   only at the end is why an early version appeared to do nothing for a whole minute.
    /// - Parameter isCancelled: checked between tiles. A minutes-long job that cannot be stopped is
    ///   not a feature, and stopping mid-tile would leave a half-refined square.
    public func run(_ image: CGImage,
                    request: Request,
                    conditioning: Conditioning,
                    tiles: JobStore.TileSet? = nil,
                    preview: @escaping @Sendable (CGImage?) -> Void = { _ in },
                    progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in },
                    steps: @escaping @Sendable (Progress) -> Void = { _ in },
                    resuming checkpoint: Checkpoint? = nil,
                    checkpointing: @escaping @Sendable (Checkpoint) -> Void = { _ in },
                    isCancelled: @escaping @Sendable () -> Bool = { false }) throws -> CGImage {

        let settings = request.settings
        let width = image.width, height = image.height
        let grid = Self.grid(width: width, height: height,
                             tile: settings.tile, overlap: settings.overlap)
        let total = grid.count
        // The same function an interface calls to size its progress bar before the pass starts. Two
        // expressions for one number is how a countdown ends up disagreeing with the loop it counts.
        let plan = Self.plan(for: settings, width: width, height: height)
        let stepsPerTile = plan.stepsPerTile

        // Refused before the pipeline is loaded, so an invalid preset costs a thrown error rather
        // than 870 MB and an out-of-bounds trap several seconds later.
        guard plan.isRunnable else {
            throw RuntimeError.strengthTooLowForStepCount(
                strength: settings.strength, steps: settings.steps,
                minimumStrength: Self.minimumStrength(forSteps: settings.steps))
        }

        try tiles?.prepare()
        let alreadyDone = tiles?.completed() ?? []
        let outstanding = TileLedger.remaining(total: total, completed: alreadyDone)

        // Loaded on first use. A pass resumed with one tile left must not pay ~870 MB and several
        // seconds for a pipeline it will use once — and one resumed with none left must not load it.
        var pipeline: StableDiffusionPipeline?
        defer { pipeline?.unloadResources() }
        func loaded() throws -> StableDiffusionPipeline {
            if let pipeline { return pipeline }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            var built = try StableDiffusionPipeline(resourcesAt: resourcesURL,
                                                    controlNet: [controlNetName],
                                                    configuration: configuration,
                                                    disableSafety: true,
                                                    reduceMemory: true)
            // See the note on this type: without it the unet is re-read from disk between every
            // tile, which is nine times the wall clock for the same peak.
            built.retainsDenoisingModels = true
            try built.loadResources()
            pipeline = built
            return built
        }

        var canvas = [Float](repeating: 0, count: width * height * 3)
        var weights = [Float](repeating: 0, count: width * height)
        let ramp = Self.feather(size: settings.tile, overlap: settings.overlap)
        let base = Self.rgba(of: image, width: width, height: height)

        var done = 0
        progress(TileLedger.progress(total: total, completed: alreadyDone).done, total)

        for (index, origin) in grid.enumerated() {
            try autoreleasepool {
                if isCancelled() { throw RuntimeError.cancelled }

                let rect = CGRect(x: origin.x, y: origin.y,
                                  width: settings.tile, height: settings.tile)

                // Accumulation is a weighted sum, so replaying stored tiles in grid order rebuilds
                // exactly the canvas the interrupted run had. Order does not matter; presence does.
                if !outstanding.contains(index), let restored = tiles?.load(index) {
                    Self.accumulate(restored, into: &canvas, weights: &weights,
                                    at: origin, canvas: (width, height), ramp: ramp)
                    done += 1
                    return
                }

                guard let patch = image.cropping(to: rect) else { return }
                let control: CGImage
                switch conditioning {
                case .theTileItself:
                    control = patch
                case .aligned(let map):
                    guard let cropped = map.cropping(to: rect) else { return }
                    control = cropped
                }

                var configuration = StableDiffusionPipeline.Configuration(prompt: request.prompt)
                configuration.startingImage = patch
                configuration.strength = settings.strength
                configuration.stepCount = settings.steps
                // The same seed for every tile. Different seeds make neighbouring tiles invent
                // incompatible detail, and no amount of overlap blends away a disagreement about
                // what the picture contains.
                configuration.seed = request.seed
                configuration.guidanceScale = settings.guidanceScale
                configuration.negativePrompt = request.negativePrompt
                configuration.disableSafety = true
                configuration.schedulerType = .dpmSolverMultistepScheduler
                configuration.controlNetInputs = [control]

                // Mid-tile resumption applies to **one** tile: the one that was in flight when the
                // pass stopped. Everything before it came back from disk; everything after starts
                // clean. Applying it to any other tile would splice one tile's latents into
                // another's, which produces a plausible picture that is quietly wrong.
                if let checkpoint, checkpoint.tile == index, checkpoint.step > 0,
                   checkpoint.step < stepsPerTile {
                    configuration.resumePoint = ResumePoint(step: checkpoint.step,
                                                            latents: checkpoint.latents,
                                                            modelOutputs: checkpoint.modelOutputs,
                                                            lowerOrderStepped: checkpoint.lowerOrderStepped)
                }

                let produced = try loaded().generateImages(configuration: configuration) { state in
                    steps(Progress(tile: index, totalTiles: total,
                                   stepInTile: state.step + 1, stepsPerTile: stepsPerTile))
                    // Offered from the generation thread, synchronously, before the next step
                    // starts. Handing it to another queue means the process can die with the
                    // checkpoint still in flight — the one moment it exists for.
                    if let resume = state.resumeState,
                       resume.completedSteps % Self.checkpointInterval == 0 {
                        checkpointing(Checkpoint(tile: index,
                                                 step: resume.completedSteps,
                                                 lowerOrderStepped: resume.lowerOrderStepped,
                                                 latents: resume.latents,
                                                 modelOutputs: resume.modelOutputs))
                    }
                    return !isCancelled()
                }
                guard let refined = produced.compactMap({ $0 }).first else {
                    throw RuntimeError.cancelled
                }

                // Written before it is accumulated: a crash between the two costs a re-render,
                // whereas accumulating first and crashing before the write loses the tile silently.
                try tiles?.store(refined, at: index)
                Self.accumulate(refined, into: &canvas, weights: &weights,
                                at: origin, canvas: (width, height), ramp: ramp)
                done += 1
                preview(try? Self.compose(canvas: canvas, weights: weights, base: base,
                                          width: width, height: height))
                progress(done, total)
            }
        }

        // Let go of ~870 MB **before** composing. `compose` allocates the full-size output twice
        // over, and paying that on top of a resident unet is the difference between finishing and
        // being killed.
        pipeline?.unloadResources()
        pipeline = nil

        return try Self.compose(canvas: canvas, weights: weights, base: base,
                                width: width, height: height)
    }

    public enum RuntimeError: Error, Equatable {
        case cancelled
        case couldNotCompose
        /// `strength × steps` rounded down to zero, so the schedule is empty.
        ///
        /// Refused here rather than allowed through, because what happens downstream is not a gentle
        /// no-op: `Scheduler.addNoise` indexes `timeSteps[startStep]` where `startStep == stepCount`,
        /// which is one past the end. That is an out-of-bounds read on a Swift array — a trap, in
        /// Apple's code, from a configuration an app is free to set.
        ///
        /// Carries the fix rather than just the complaint: raise strength above `minimumStrength`,
        /// or raise `steps`. It is a *pair* that is invalid, and an app that only surfaces the
        /// strength will send someone hunting the wrong dial.
        case strengthTooLowForStepCount(strength: Float, steps: Int, minimumStrength: Float)
    }

    // MARK: Composition

    /// 1 through the middle, ramping to 0 across the overlap at each edge. Even overlapped, adjacent
    /// tiles disagree slightly in the shared region; a linear cross-fade hides it, and a hard cut is
    /// *more* visible than the seam it replaced.
    static func feather(size: Int, overlap: Int) -> [Float] {
        var line = [Float](repeating: 1, count: size)
        for i in 0..<min(overlap, size / 2) {
            let v = Float(i) / Float(max(overlap - 1, 1))
            line[i] = v
            line[size - 1 - i] = v
        }
        var plane = [Float](repeating: 0, count: size * size)
        for row in 0..<size {
            for column in 0..<size {
                plane[row * size + column] = line[row] * line[column]
            }
        }
        return plane
    }

    static func accumulate(_ tile: CGImage,
                           into canvas: inout [Float],
                           weights: inout [Float],
                           at origin: (x: Int, y: Int),
                           canvas size: (width: Int, height: Int),
                           ramp: [Float]) {
        let w = tile.width, h = tile.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &pixels, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        context.draw(tile, in: CGRect(x: 0, y: 0, width: w, height: h))

        for row in 0..<h {
            let canvasRow = origin.y + row
            guard canvasRow < size.height else { break }
            for column in 0..<w {
                let canvasColumn = origin.x + column
                guard canvasColumn < size.width else { break }
                let weight = ramp[row * w + column]
                guard weight > 0 else { continue }
                let source = (row * w + column) * 4
                let target = (canvasRow * size.width + canvasColumn) * 3
                canvas[target]     += Float(pixels[source]) * weight
                canvas[target + 1] += Float(pixels[source + 1]) * weight
                canvas[target + 2] += Float(pixels[source + 2]) * weight
                weights[canvasRow * size.width + canvasColumn] += weight
            }
        }
    }

    /// What has been refined so far, over the picture that was already there.
    ///
    /// Pixels no tile has touched fall back to `base`. Without that they would divide by a near-zero
    /// weight and come out black, so an early preview would be one bright square on a dark field
    /// rather than a picture gaining detail.
    static func compose(canvas: [Float], weights: [Float], base: [UInt8],
                        width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            let weight = weights[index]
            guard weight > 1e-6 else {
                pixels[index * 4]     = base[index * 4]
                pixels[index * 4 + 1] = base[index * 4 + 1]
                pixels[index * 4 + 2] = base[index * 4 + 2]
                continue
            }
            pixels[index * 4]     = UInt8(min(max(canvas[index * 3] / weight, 0), 255))
            pixels[index * 4 + 1] = UInt8(min(max(canvas[index * 3 + 1] / weight, 0), 255))
            pixels[index * 4 + 2] = UInt8(min(max(canvas[index * 3 + 2] / weight, 0), 255))
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height,
                                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil,
                                  shouldInterpolate: true, intent: .defaultIntent)
        else { throw RuntimeError.couldNotCompose }
        return image
    }

    static func rgba(of image: CGImage, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return pixels }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    /// Square resample, for bringing a master down to the working size and putting the result back.
    public static func resized(_ image: CGImage, toWidth side: Int) -> CGImage? {
        guard side > 0, image.width != side else { return image }
        let height = Int((Double(side) / Double(image.width) * Double(image.height)).rounded())
        guard let context = CGContext(data: nil, width: side, height: max(height, 1),
                                      bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: max(height, 1)))
        return context.makeImage()
    }
}
