import Foundation

/// The shape of a generation before any pixels exist: how many steps, which of them decode a
/// latent, and when the UI stops being a progress capsule and becomes a picture frame.
///
/// It is a pure value so the schedule can be tested without waiting 20 seconds, and so the mock
/// and the real pipeline can be driven by the same numbers.
public struct GenerationPlan: Sendable, Equatable {
    public let totalSteps: Int
    /// A latent is decoded every `previewCadence` steps. The design bundle asks for "every 2–3
    /// steps": 2 keeps the picture visibly moving without costing a VAE decode on every step.
    public let previewCadence: Int
    /// The step at which the capsule grows into the picture frame (bundle 1b: "~ step 5+", as the
    /// first latent decodes). Before this the user is looking at a progress capsule; after it,
    /// at a picture.
    public let frameRevealStep: Int
    /// Blur over the first preview, in points, easing to zero by the last one (bundle 1b: 26 → 0).
    public let initialVeilBlur: Double
    /// The milk veil's white overlay opacity while the image is forming.
    public let veilOpacity: Double

    public init(totalSteps: Int = 28,
                previewCadence: Int = 2,
                frameRevealStep: Int = 5,
                initialVeilBlur: Double = 26,
                veilOpacity: Double = 0.22) {
        precondition(totalSteps > 0, "a generation with no steps is not a generation")
        precondition(previewCadence > 0, "cadence must be positive")
        self.totalSteps = totalSteps
        self.previewCadence = previewCadence
        self.frameRevealStep = frameRevealStep
        self.initialVeilBlur = initialVeilBlur
        self.veilOpacity = veilOpacity
    }

    /// Steps 1, 3, 5 … and always the last one, whatever the cadence says — finishing a generation
    /// without decoding the final latent would show the user the second-to-last picture forever.
    public func emitsPreview(atStep step: Int) -> Bool {
        guard step >= 1, step <= totalSteps else { return false }
        if step == totalSteps { return true }
        return (step - 1) % previewCadence == 0
    }

    public var previewSteps: [Int] { (1...totalSteps).filter(emitsPreview(atStep:)) }

    /// True once the first latent has been decoded and the frame has taken over from the capsule.
    public func showsFrame(atStep step: Int) -> Bool { step >= frameRevealStep }

    /// Veil blur in points at a given step: `initialVeilBlur` over the first preview, 0 over the
    /// last. Between previews it holds — the veil lifts when a new picture arrives, not on a timer.
    public func veilBlur(atStep step: Int) -> Double {
        let previews = previewSteps
        guard let last = previews.last, previews.count > 1 else { return 0 }
        let delivered = previews.filter { $0 <= step }
        guard let current = delivered.last else { return initialVeilBlur }
        guard let first = previews.first, last > first else { return 0 }
        let travelled = Double(current - first) / Double(last - first)
        return initialVeilBlur * (1 - travelled)
    }

    /// How far along the bar is. The only place a fraction is legitimate.
    public func fraction(atStep step: Int) -> Double {
        min(1, max(0, Double(step) / Double(totalSteps)))
    }

    public static let standard = GenerationPlan()
}

/// Turns a `GenerationPlan` into the concrete list of things that happen, in order.
///
/// The mock generator walks this list, sleeping `stepDuration` between entries. Tests walk the same
/// list with no sleeping at all, which is how the whole 28-step state space is covered in
/// milliseconds instead of half a minute.
public struct GenerationSchedule: Sendable, Equatable {
    public struct Step: Sendable, Equatable {
        public let index: Int
        public let emitsPreview: Bool
        public let showsFrame: Bool
        public let veilBlur: Double
        public let fraction: Double
    }

    public let plan: GenerationPlan
    public let steps: [Step]

    public init(plan: GenerationPlan = .standard) {
        self.plan = plan
        self.steps = (1...plan.totalSteps).map { i in
            Step(index: i,
                 emitsPreview: plan.emitsPreview(atStep: i),
                 showsFrame: plan.showsFrame(atStep: i),
                 veilBlur: plan.veilBlur(atStep: i),
                 fraction: plan.fraction(atStep: i))
        }
    }

    /// Wall-clock length of a run at a given per-step cost. Used to check the mock lands in the
    /// 10–30 s window a real on-device diffusion actually takes.
    public func duration(perStep: Duration) -> Duration { perStep * plan.totalSteps }
}
