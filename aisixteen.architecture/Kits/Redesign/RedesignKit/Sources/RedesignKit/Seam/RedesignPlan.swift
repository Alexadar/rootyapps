import Foundation

/// The four named stages, from the design handoff.
///
/// The raw values ARE the user-facing strings — `GeneratingView` prints `stage.rawValue` directly.
/// Do not "tidy" them: they were written to make a three-minute wait legible, and the difference
/// between "Composing" and "Composing the redesign" is the difference between a progress label and
/// a sentence that tells you what the machine is doing.
public enum GenerationStage: String, Sendable, Codable, CaseIterable, Hashable {
    case reading = "Reading the space"
    case composing = "Composing the redesign"
    case refining = "Refining details"
    case fullRes = "Full resolution"
}

/// The shape of a run: how many steps, where the stages fall, how often a preview and a checkpoint
/// are offered, and how expensive each stage's step is.
///
/// Carried ON the request rather than read from a global, so a queued job that survives a relaunch
/// resumes against the same plan it started under — otherwise a later build with different
/// step counts would resume a checkpoint into a different-shaped run.
public struct RedesignPlan: Sendable, Equatable, Codable, Hashable {
    public let totalSteps: Int
    /// Inclusive, 1-based, contiguous, covering 1...totalSteps.
    public let stageRanges: [StageRange]
    /// Decode a latent every N steps. The forming image is the whole reason a multi-minute wait
    /// is bearable, but decoding costs real time, so it is not every step.
    public let previewCadence: Int
    /// Offer a resumable checkpoint every N steps.
    public let checkpointCadence: Int
    public let veilBlurStart: Double
    public let veilOpacity: Double
    /// Relative cost of one step in each stage.
    ///
    /// Full resolution is one very long step — the VAE decode at full size — and treating every
    /// step as equal collapses the estimate to "1 min left" and then hangs there for ninety
    /// seconds. That is precisely the lie the handoff's "time-left is a rolling estimate from
    /// measured step duration" exists to prevent.
    public let stageCostWeight: [StageWeight]

    public struct StageRange: Sendable, Equatable, Codable, Hashable {
        public let stage: GenerationStage
        public let lowerBound: Int
        public let upperBound: Int
        public init(stage: GenerationStage, lowerBound: Int, upperBound: Int) {
            self.stage = stage
            self.lowerBound = lowerBound
            self.upperBound = upperBound
        }
        public func contains(_ step: Int) -> Bool { step >= lowerBound && step <= upperBound }
    }

    public struct StageWeight: Sendable, Equatable, Codable, Hashable {
        public let stage: GenerationStage
        public let weight: Double
        public init(stage: GenerationStage, weight: Double) {
            self.stage = stage
            self.weight = weight
        }
    }

    public init(totalSteps: Int,
                stageRanges: [StageRange],
                previewCadence: Int,
                checkpointCadence: Int,
                veilBlurStart: Double,
                veilOpacity: Double,
                stageCostWeight: [StageWeight]) {
        self.totalSteps = totalSteps
        self.stageRanges = stageRanges
        self.previewCadence = previewCadence
        self.checkpointCadence = checkpointCadence
        self.veilBlurStart = veilBlurStart
        self.veilOpacity = veilOpacity
        self.stageCostWeight = stageCostWeight
    }

    /// The boundaries the design handoff's mock established, kept because the HTML board's
    /// "step 18 of 32 · Refining details" has to remain true.
    ///
    /// ⚠️ **`totalSteps` IS A MOCK NUMBER. Do not carry 32 into the model integration.**
    ///
    /// The real count is arithmetic, available with no model and no disk, and it is not 32:
    ///
    ///     let real = TiledControlNetPass.plan(for: settings, width: side, height: side)
    ///     real.totalTiles · real.stepsPerTile · real.totalSteps
    ///
    /// `stepsPerTile` comes from `calculateTimesteps(strength:)` — what the scheduler will
    /// ACTUALLY run, not the nominal setting. Image-to-image skips the early schedule, so a
    /// nominal 32 at strength 0.5 runs **16**. Reporting the nominal number gives a counter that
    /// stalls partway and then jumps, which is precisely the dishonesty the named stages and the
    /// measured estimate exist to avoid. Build the plan from `real`, and move the stage boundaries
    /// with it — this whole type is data on the request for exactly that reason.
    ///
    /// ⚠️ **When a `strength` setting arrives, it is COUPLED to `totalSteps` and the coupling has
    /// a crash on the wrong side of it.** Apple's scheduler computes
    /// `startStep = steps - Int(steps × strength)`; when `steps × strength` floors to zero,
    /// `addNoise` indexes `timeSteps[stepCount]`, one past the end, and traps. The *gentlest*
    /// setting is the one that dies, and the two values are usually owned by different code —
    /// a sibling app missed safety by three thousandths.
    ///
    /// There is no `strength` in this app today (presets are prompt macros; a strength dial is
    /// Studio's grammar, not this one's), so nothing here can trip it. **If one is ever added:**
    ///
    ///     let safe = TiledControlNetPass.clamped(strength: curve(rail), forSteps: steps)
    ///
    /// **CLAMP THE MAPPING. Do not assert a table of preset values.** That was the first advice
    /// given for this and it is the version that fails: a continuous control's named detents are
    /// labels on an interval, not the value set. Measured on the sibling's rail at `steps: 12`,
    /// **84 of 1001 reachable positions** produce an empty schedule — so fixing the four named
    /// values leaves 84 live crashes behind a green test. Exactly the original defect one level
    /// up: valid where someone enumerated, fatal where they did not. This app's strength, if it
    /// ever has one, is likelier to come from a slider than a table.
    ///
    /// `clamped` only ever raises and never moves an already-valid value. `run` still throws
    /// rather than clamping, so a hardcoded strength in source stays a loud programmer error.
    /// Cost: about **0.7 ms per `plan()` call in Debug** — the scheduler's beta tables dominate.
    /// Fine once per pass; wrong in anything per-frame. (An earlier note said "microseconds";
    /// it was measured since and that figure was wrong.)
    ///
    /// And before designing any such control: **ask how many outcomes it can actually produce.**
    /// A slider's resolution is `steps × the fraction of the range it uses`, not `steps` — so a
    /// range-capped rail has far fewer distinct results than positions, and a third of its travel
    /// can land on the same picture. Ask the base rather than quoting a number that goes stale:
    ///
    ///     TiledControlNetPass.distinctOutcomes(forSteps: 12, strengthFrom: 0, to: 0.5)   // 6
    ///
    /// This app would cap harder than most — a redesign has even less business at 0.9 than an
    /// enhance does — so the honest control here may be a few named choices rather than a rail
    /// that pretends to a precision the scheduler cannot deliver.
    ///
    /// ⚠️ **But do not over-apply that.** The rule is not "sliders are dishonest"; it is:
    /// **a control that resolves to a STEP COUNT should be discrete; a control that resolves to a
    /// BLEND should not.** Only the first is quantised by the scheduler. The second never touches
    /// it and is genuinely continuous.
    ///
    /// That rule now lives in `../aisixteen.models/swift/README.md` (strength-cliff section) and
    /// **that copy is the authority** — everything from here to the end of this comment is a local
    /// restatement, kept because it names this app's own types. If the two ever disagree, the
    /// shared file is right. A rule that exists only as private doc comments in two apps is
    /// precisely the arrangement where the third reader gets the version that was wrong, which is
    /// how this paragraph came to be corrected twice.
    ///
    /// This app already has one of each, and they must not be reasoned about together:
    /// a hypothetical strength would resolve to steps and should be discrete, while
    /// `ResultModel.wipe` — the before/after comparison, this app's signature control — is a pure
    /// blend. It is continuous, it is correct that it is continuous, and nothing on this page
    /// applies to it.
    public static let standard = RedesignPlan(
        totalSteps: 32,
        stageRanges: [
            .init(stage: .reading, lowerBound: 1, upperBound: 4),
            .init(stage: .composing, lowerBound: 5, upperBound: 12),
            .init(stage: .refining, lowerBound: 13, upperBound: 28),
            .init(stage: .fullRes, lowerBound: 29, upperBound: 32),
        ],
        previewCadence: 2,
        // Four steps. At a few seconds a step that is well under twenty seconds of work at risk,
        // and an atomic write of ~1 MB is nothing against a step that takes seconds.
        checkpointCadence: 4,
        veilBlurStart: 26,
        veilOpacity: 0.22,
        stageCostWeight: [
            .init(stage: .reading, weight: 0.4),
            .init(stage: .composing, weight: 1.0),
            .init(stage: .refining, weight: 1.0),
            .init(stage: .fullRes, weight: 6.0),
        ]
    )

    public func stage(atStep step: Int) -> GenerationStage {
        stageRanges.first { $0.contains(step) }?.stage
            ?? (step < 1 ? .reading : .fullRes)
    }

    public func weight(of stage: GenerationStage) -> Double {
        stageCostWeight.first { $0.stage == stage }?.weight ?? 1.0
    }

    /// The final step always emits a preview — it is the finished picture, and "the last frame the
    /// user saw was step 30" is a visible glitch at the moment the result appears.
    public func emitsPreview(atStep step: Int) -> Bool {
        guard step >= 1, step <= totalSteps else { return false }
        return step == totalSteps || step % previewCadence == 0
    }

    /// The final step never offers a checkpoint. Resuming "from step 32 of 32" is a run with no
    /// work left in it; the output is what should have been saved.
    public func offersCheckpoint(atStep step: Int) -> Bool {
        guard step >= 1, step < totalSteps else { return false }
        return step % checkpointCadence == 0
    }

    /// The milk veil: white .22 over the forming image, blur easing 26 → 0 across the run.
    public func veilBlur(atStep step: Int) -> Double {
        guard totalSteps > 0 else { return 0 }
        let fraction = Double(max(0, min(step, totalSteps))) / Double(totalSteps)
        return veilBlurStart * (1 - fraction)
    }

    /// Work still to do after `step`, in "one standard step" units. The estimator multiplies this
    /// by its measured seconds-per-weighted-step.
    public func weightedRemaining(afterStep step: Int) -> Double {
        guard step < totalSteps else { return 0 }
        var total = 0.0
        for next in (max(step, 0) + 1)...totalSteps {
            total += weight(of: stage(atStep: next))
        }
        return total
    }

    /// Total weighted work in a whole run. Used to seed an estimate before anything is measured.
    public var weightedTotal: Double { weightedRemaining(afterStep: 0) }
}
