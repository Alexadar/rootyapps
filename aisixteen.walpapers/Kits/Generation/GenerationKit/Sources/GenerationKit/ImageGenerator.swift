import Foundation

/// A picture decoded part-way through generation.
///
/// Raw pixels rather than a `UIImage`/`NSImage`, because this package is Foundation-only and
/// because a real pipeline hands back a buffer. The app turns it into a platform image once.
public struct PreviewImage: Sendable, Equatable {
    /// 8-bit RGBA, `size.width * size.height * 4` bytes, row-major, no padding.
    public let pixels: Data
    public let size: AspectRatio

    public init(pixels: Data, size: AspectRatio) {
        self.pixels = pixels
        self.size = size
    }

    /// The byte count a buffer of this size must have. Cheap guard against a renderer that
    /// silently produced the wrong stride.
    public var expectedByteCount: Int { size.pixelCount * 4 }
    public var isWellFormed: Bool { pixels.count == expectedByteCount }
}

/// One diffusion step's worth of news.
///
/// **Why this is not a `Double` from 0 to 1.** Three things would be lost. The UI is specified to
/// print the literal string "Step 9 of 28", which a fraction cannot reconstruct. Latents decode
/// every two or three steps, so most steps carry no picture at all — a fraction has no way to say
/// "nothing new to show". And a real `StableDiffusionPipeline` progress handler already hands over
/// exactly this shape, so the adapter for the real model is a field rename rather than a redesign.
/// A fraction would force the pipeline to throw away information the UI needs, at the one boundary
/// this whole run exists to get right.
public struct GenerationProgress: Sendable, Equatable {

    /// Which subtask is reporting.
    ///
    /// It exists because the two count different things. An earlier version presented enlargement as
    /// extra diffusion steps — a 28-step generation reported "step 37 of 37" once the nine ESRGAN
    /// tiles were added on — which contradicts the step count the user set in Advanced and makes a
    /// resumed run look like it overran. The counter should be continuous, and the *unit* should be
    /// named honestly.
    public enum Stage: String, Sendable, Equatable {
        case generating
        case enlarging
    }

    public let stage: Stage
    /// 1-based index of the unit that just completed — a step while generating, a tile while
    /// enlarging.
    public let step: Int
    /// Total units for **this stage**. Known up front; neither stage is open-ended.
    public let totalSteps: Int
    /// The latent decoded at this step, or `nil` on the steps that decode nothing.
    public let preview: PreviewImage?

    public init(step: Int, totalSteps: Int, preview: PreviewImage?, stage: Stage = .generating) {
        self.stage = stage
        self.step = step
        self.totalSteps = totalSteps
        self.preview = preview
    }

    /// Only for drawing a bar. Never the transport type.
    public var fraction: Double {
        guard totalSteps > 0 else { return 0 }
        return min(1, max(0, Double(step) / Double(totalSteps)))
    }

    public var isFinalStep: Bool { step >= totalSteps }
}

/// A finished wallpaper, with everything needed to reproduce it.
public struct GeneratedImage: Sendable, Equatable {
    /// 8-bit RGBA, as `PreviewImage`.
    public let pixels: Data
    public let size: AspectRatio
    public let prompt: String
    /// Kept so "regenerate from this prompt" can deliberately roll a *different* seed, and so a
    /// picture the user liked can be reproduced exactly.
    public let seed: UInt32
    public let createdAt: Date

    public init(pixels: Data, size: AspectRatio, prompt: String, seed: UInt32, createdAt: Date) {
        self.pixels = pixels
        self.size = size
        self.prompt = prompt
        self.seed = seed
        self.createdAt = createdAt
    }
}

public enum GenerationError: Error, Sendable, Equatable {
    /// The model is not installed. Should be unreachable — the gate stands in front of Create.
    case modelUnavailable
    /// The device ran out of memory mid-generation. The one failure a real pipeline actually has
    /// on a phone, and the reason the failure card names a reason instead of saying "error".
    case outOfMemory
    /// The user cancelled, or the enclosing `Task` was cancelled.
    case cancelled
    case failed(reason: String)

    /// Plain words for the failure card. No error codes, no "an error occurred".
    public var plainReason: String {
        switch self {
        case .modelUnavailable: return "The image model isn't on this device yet."
        case .outOfMemory:      return "This device ran out of room to work in. A smaller size will fit."
        case .cancelled:        return "You stopped it."
        case .failed(let r):    return r
        }
    }
}

/// **The seam.** Everything in the app talks to this; nothing talks to a model.
///
/// `MockImageGenerator` and `FailingImageGenerator` implement it today. A Core ML or MLX diffusion
/// pipeline implements it later, and no view changes.
/// Everything a generation needs, as one value.
///
/// A struct rather than more parameters on `generate`: negative prompt and per-stage step counts
/// arrived after the protocol was written, and each new argument would have been a breaking change
/// rippling through both mocks and every call site. Adding a field with a default is not.
public struct GenerationRequest: Sendable, Equatable {
    public var prompt: String
    /// What the model should avoid. CLIP truncates at 77 tokens **silently**, so an over-long
    /// negative quietly loses its tail.
    public var negativePrompt: String
    public var aspect: AspectRatio
    public var seed: UInt32?
    /// Diffusion steps for stage 1. More is not automatically better — past ~30 the picture stops
    /// changing and only the wait grows.
    public var steps: Int
    public var guidanceScale: Float
    /// Stage 2. Off yields a smaller wallpaper, not a broken one.
    public var upscale: Bool

    public init(prompt: String,
                negativePrompt: String = "",
                aspect: AspectRatio = .phone,
                seed: UInt32? = nil,
                steps: Int = 28,
                guidanceScale: Float = 7.5,
                upscale: Bool = true) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.aspect = aspect
        self.seed = seed
        self.steps = steps
        self.guidanceScale = guidanceScale
        self.upscale = upscale
    }
}

/// One compiled graph the model is made of.
///
/// The app ships six; a generation loads three of them into memory. Naming them once here is what
/// lets the waking capsule say "Image model ready" instead of a number with no subject.
public struct ModelPart: Sendable, Equatable, Identifiable {
    /// Stable across releases — it is written into the warmth marker, so renaming one silently
    /// re-tunes that part on every launch.
    public let id: String
    /// What a person is told. "Image model", not "ControlledUnet.mlmodelc".
    public let name: String
    public let bytes: Int64

    public init(id: String, name: String, bytes: Int64) {
        self.id = id
        self.name = name
        self.bytes = bytes
    }
}

/// Progress through the one-time Neural Engine compile.
///
/// Counted in **parts completed**, never in seconds. There is nothing measurable inside a single
/// compile, and the whole point of the pass is to be honest about a wait it cannot predict.
public enum TuningEvent: Sendable, Equatable {
    case began(part: ModelPart, index: Int, of: Int)
    case finished(part: ModelPart, index: Int, of: Int, seconds: Double)
    /// The pass yielded — something the user asked for wants the models.
    case stoodDown(after: Int, of: Int)
    case failed(part: ModelPart, reason: String)
}

/// One component of the model becoming resident.
///
/// Replaces a bare `Double` so the interface can say *which* part just landed. "Image model ready ·
/// 89%" is a sequence the user can read as progress; one arc that never changes for two minutes is
/// not, however truthful the number behind it.
public struct PreparationProgress: Sendable, Equatable {
    /// Byte-weighted, 0→1. Every value is a real measurement of how much is loaded, never a timer.
    public let fraction: Double
    /// The component that just finished loading. `nil` before the first one lands — and that is why
    /// the UI shows no percentage yet, because "0%" is a stopped counter.
    public let part: ModelPart?
    /// 1-based. Zero before the first part lands.
    public let index: Int
    public let total: Int

    public init(fraction: Double, part: ModelPart?, index: Int, total: Int) {
        self.fraction = fraction
        self.part = part
        self.index = index
        self.total = total
    }
}

public protocol ImageGenerator: Sendable {
    /// - Parameter seed: `nil` means roll one. The chosen seed comes back on `GeneratedImage`.
    /// - Parameter progress: called once per completed step, on an arbitrary executor. The caller
    ///   is responsible for hopping to the main actor.
    func generate(_ request: GenerationRequest,
                  progress: @escaping @Sendable (GenerationProgress) -> Void) async throws -> GeneratedImage

    /// Load whatever has to be in memory before a step can run, and return once it is.
    ///
    /// This exists because the real model takes a long time to become usable — hundreds of
    /// megabytes read from disk — and that time is invisible to `generate`'s progress handler,
    /// which cannot report a step until there are steps. Without a separate call for it, the UI has
    /// no way to tell "loading" from "running", and shows a frozen step counter for the whole load.
    /// That is precisely the lying progress indicator the brief rules out.
    ///
    /// Must be idempotent and safe to call speculatively — the app calls it while the user is still
    /// typing, so that by the time they tap Create the wait has already been paid.
    /// - Parameter reporting: called as each component becomes resident, with the byte-weighted
    ///   fraction and the part that just landed. Coarse by nature — see `CoreMLImageGenerator` — but
    ///   every value is a real measurement, never a timer.
    func prepare(reporting: @escaping @Sendable (PreparationProgress) -> Void) async throws

    /// Every graph the Neural Engine has to compile, in the order the pass takes them.
    var tunableParts: [ModelPart] { get }

    /// Force the Neural Engine's one-time compilation for each part, releasing the memory again.
    ///
    /// Distinct from `prepare`: that leaves the model resident and ready, this leaves nothing
    /// resident. The compile is cached by the system, keyed to hardware and OS build, and costs
    /// minutes the first time.
    ///
    /// - Parameter skipping: ids a previous launch already finished.
    /// - Parameter shouldStandDown: checked between parts, so the pass yields the moment the user
    ///   asks for something. It is background work by definition.
    func tune(skipping: Set<String>,
              shouldStandDown: @escaping @Sendable () -> Bool,
              reporting: @escaping @Sendable (TuningEvent) -> Void) async

    /// Release everything held in memory. The app calls this before another model needs the room.
    func unload()

    /// Whether `generate` can start producing steps immediately.
    var isReady: Bool { get }

    /// Stop as soon as the current step ends.
    ///
    /// This exists **in addition to** Swift's `Task` cancellation, and it is not redundant. A real
    /// pipeline spends its time inside a single non-cancellable `MLModel.prediction` call; the only
    /// thing that can stop it is a flag the step loop reads between predictions. Implementations
    /// honour both doors — `Task.checkCancellation()` between steps *and* this flag — so a caller
    /// that cancels the task and a caller that calls `cancel()` get the same result.
    func cancel()
}

extension ImageGenerator {
    /// Convenience for callers and tests that only care about the prompt.
    public func generate(prompt: String,
                         aspect: AspectRatio = .phone,
                         seed: UInt32? = nil,
                         progress: @escaping @Sendable (GenerationProgress) -> Void) async throws -> GeneratedImage {
        try await generate(GenerationRequest(prompt: prompt, aspect: aspect, seed: seed),
                           progress: progress)
    }

    /// Generators with nothing to load — the mocks, and any future pipeline that is cheap to
    /// start — inherit these and need no code.
    public func prepare(reporting: @escaping @Sendable (PreparationProgress) -> Void) async throws {}
    public func prepare() async throws { try await prepare(reporting: { _ in }) }
    public var tunableParts: [ModelPart] { [] }
    public func tune(skipping: Set<String>,
                     shouldStandDown: @escaping @Sendable () -> Bool,
                     reporting: @escaping @Sendable (TuningEvent) -> Void) async {}
    public func unload() {}
    public var isReady: Bool { true }

    /// Kept for callers that only want the number. **Deliberately an extension, not a requirement**:
    /// nothing has to implement it, so a generator cannot accidentally satisfy the protocol by
    /// providing only the narrow version and silently lose the component names.
    public func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        try await prepare(reporting: { progress($0.fraction) })
    }
}
