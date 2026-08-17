import Foundation
import ModelKit

/// Everything needed to decide whether half-finished work still applies.
///
/// The manifest exists to answer one question honestly: *is the work on disk still the work the
/// user asked for?* Resuming when the answer is no does not fail loudly — it splices two different
/// pictures together and looks like a bug in the model. So every parameter that can change the
/// output is recorded, and any difference discards rather than adapts.
public struct JobManifest: Codable, Equatable, Sendable {

    public enum Kind: Codable, Equatable, Sendable {
        case generate
        /// Refining a wallpaper that already exists, identified by its library record.
        case enhance(recordID: String)
    }

    /// Where the work got to. Deliberately carries the *unit* as well as the count, because the UI
    /// reports completed units and never elapsed time.
    public enum Stage: Codable, Equatable, Sendable {
        case diffusing(step: Int, of: Int)
        case upscaling(tile: Int, of: Int)
        case refining(tile: Int, of: Int)
        /// Everything computed; only the cheap deterministic tail is left.
        case finishing

        public var isComplete: Bool { if case .finishing = self { return true }; return false }

        /// The same truth in a chip's worth of room: "enhancing · 2 of 9".
        ///
        /// Shorter than `summary`, and shortened in the one way that keeps it honest — the unit name
        /// goes, the *numbers* stay. A chip reading "enhancing · 22%" would be inventing a
        /// percentage out of a count, which is the one thing every indicator in this app is written
        /// not to do.
        public var chipSummary: String {
            switch self {
            case .diffusing(let step, let total): return "generating · \(step) of \(total)"
            case .upscaling(let tile, let total): return "enlarging · \(tile) of \(total)"
            case .refining(let tile, let total): return "enhancing · \(tile) of \(total)"
            case .finishing: return "finishing"
            }
        }

        /// "enhancing, 2 of 4 tiles" — the same vocabulary the job used while it was running, so
        /// resuming reads as continuing rather than as something new.
        public var summary: String {
            switch self {
            case .diffusing(let step, let total): return "generating, step \(step) of \(total)"
            case .upscaling(let tile, let total): return "enlarging, \(tile) of \(total) tiles"
            case .refining(let tile, let total): return "enhancing, \(tile) of \(total) tiles"
            case .finishing: return "finishing"
            }
        }
    }

    public var id: String
    public var kind: Kind
    public var prompt: String
    public var negativePrompt: String
    public var seed: UInt32
    public var steps: Int
    public var guidanceScale: Float
    public var aspect: AspectRatio
    /// Enhance only. Zero for a plain generation, which is why they are compared unconditionally —
    /// a job that changes kind is a different job anyway.
    public var strength: Double
    public var tile: Int
    public var overlap: Int
    public var workingSide: Int
    /// Tile origins, in working order. **Persisted rather than recomputed**: if the tiling maths
    /// ever changes, a half-finished job must not be silently reinterpreted against a new grid.
    public var origins: [Origin]
    /// Every model this job used, **by subtask**. See `ModelUse`.
    ///
    /// A list rather than one entry because a wallpaper is made by a pipeline: stage 1 diffuses,
    /// stage 2 enlarges with a different network entirely, stage 3 refines. Recording only the
    /// diffusion model would let a changed upscaler pass unnoticed, and the stored stage-2 tiles
    /// would then be spliced into an enlargement made by a different network.
    ///
    /// Only the stages the job actually ran appear here — an Enhance depends on the refine model
    /// and nothing else.
    ///
    /// Ids are stored rather than whole model descriptions, so a manifest written by a build that
    /// knew about a model this one does not can still be *read*, recognised as foreign, and
    /// discarded — rather than failing to decode and leaving an orphaned directory forever.
    public var models: [ModelUse]
    public var stage: Stage
    public var startedAt: Date
    public var updatedAt: Date

    public struct Origin: Codable, Equatable, Sendable {
        public var x: Int
        public var y: Int
        public init(x: Int, y: Int) { self.x = x; self.y = y }
    }

    public init(id: String = UUID().uuidString,
                kind: Kind,
                prompt: String,
                negativePrompt: String,
                seed: UInt32,
                steps: Int,
                guidanceScale: Float,
                aspect: AspectRatio,
                strength: Double = 0,
                tile: Int = 0,
                overlap: Int = 0,
                workingSide: Int = 0,
                origins: [Origin] = [],
                models: [ModelUse],
                stage: Stage,
                startedAt: Date,
                updatedAt: Date) {
        self.id = id
        self.kind = kind
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.seed = seed
        self.steps = steps
        self.guidanceScale = guidanceScale
        self.aspect = aspect
        self.strength = strength
        self.tile = tile
        self.overlap = overlap
        self.workingSide = workingSide
        self.origins = origins
        self.models = models
        self.stage = stage
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    /// Whether work stored under this manifest may be reused for `other`.
    ///
    /// Compares **everything that can change a pixel** and nothing that cannot. `startedAt`,
    /// `updatedAt`, `stage` and `id` are all excluded deliberately: they describe progress, not the
    /// picture. Everything else — including the model fingerprint and the tile grid — must match
    /// exactly.
    public func describesSameWork(as other: JobManifest) -> Bool {
        kind == other.kind
            && prompt == other.prompt
            && negativePrompt == other.negativePrompt
            && seed == other.seed
            && steps == other.steps
            && guidanceScale == other.guidanceScale
            && aspect == other.aspect
            && strength == other.strength
            && tile == other.tile
            && overlap == other.overlap
            && workingSide == other.workingSide
            && origins == other.origins
            && models.describesSameModels(as: other.models)
    }

    /// A job is offerable only if it is unfinished *and* **every model it used** is still installed,
    /// unchanged.
    ///
    /// Both halves of each model's record are load-bearing, for different reasons. A different
    /// **model** means the work is not even the same kind of picture. A different **build** of the
    /// same model means the weights changed underneath a paused job, which produces a wallpaper
    /// spliced at a tile boundary with nothing anywhere reporting a problem.
    ///
    /// `installed` may list more than the job used; see `areAllStillInstalled(among:)`.
    public func canBeResumed(with installed: [ModelUse]) -> Bool {
        !stage.isComplete && models.areAllStillInstalled(among: installed)
    }
}
