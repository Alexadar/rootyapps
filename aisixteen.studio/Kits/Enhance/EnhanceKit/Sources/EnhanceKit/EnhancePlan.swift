import Foundation

/// The shape of a pass before any pixels exist: how many steps, which of them produce a preview,
/// and how the milk veil lifts.
///
/// A pure value, so the whole 20-step schedule is proved in milliseconds instead of waiting half a
/// minute for it — and so the mock and the real pipeline are driven by exactly the same numbers.
public struct EnhancePlan: Sendable, Equatable {

    /// Board `1c` says "step 9 of 20". Twenty, not the wallpaper app's twenty-eight: an
    /// image-to-image pass at moderate strength does fewer steps than a text-to-image one.
    public let totalSteps: Int

    /// A preview is decoded every `previewCadence` steps. Two keeps the picture visibly moving
    /// without paying for a decode on every step.
    public let previewCadence: Int

    /// The veil's blur over the first preview, in points, easing to zero by the last (`26 → 0`).
    public let initialVeilBlur: Double

    /// The milk veil's white overlay while the image is forming: `rgba(255,255,255,.22)`.
    public let veilOpacity: Double

    public init(totalSteps: Int = 20,
                previewCadence: Int = 2,
                initialVeilBlur: Double = 26,
                veilOpacity: Double = 0.22) {
        precondition(totalSteps > 0, "a pass with no steps is not a pass")
        precondition(previewCadence > 0, "cadence must be positive")
        self.totalSteps = totalSteps
        self.previewCadence = previewCadence
        self.initialVeilBlur = initialVeilBlur
        self.veilOpacity = veilOpacity
    }

    public static let standard = EnhancePlan()

    /// Steps 1, 3, 5 … and **always the last one**, whatever the cadence says. Finishing a pass
    /// without decoding the final preview would leave the user looking at the second-to-last
    /// picture while the capsule says it is done.
    public func emitsPreview(atStep step: Int) -> Bool {
        guard step >= 1, step <= totalSteps else { return false }
        if step == totalSteps { return true }
        return (step - 1) % previewCadence == 0
    }

    public var previewSteps: [Int] { (1...totalSteps).filter(emitsPreview(atStep:)) }

    /// The veil's blur in points at a given step.
    ///
    /// Between previews it **holds**: the veil lifts when a new picture arrives, not on a timer.
    /// A veil that eased continuously would be animating over a still frame, which reads as the
    /// interface fidgeting rather than the photo resolving.
    public func veilBlur(atStep step: Int) -> Double {
        let previews = previewSteps
        guard let first = previews.first, let last = previews.last, last > first else { return 0 }
        guard let current = previews.last(where: { $0 <= step }) else { return initialVeilBlur }
        let travelled = Double(current - first) / Double(last - first)
        return initialVeilBlur * (1 - travelled)
    }

    /// The label for a step, so no view spells it.
    public func label(atStep step: Int) -> String {
        "Enhancing · step \(step) of \(totalSteps)"
    }
}

/// A plan turned into the concrete list of things that happen, in order.
///
/// The mock walks this list sleeping between entries; the tests walk the same list with no sleeping
/// at all, which is how twenty steps are covered in microseconds.
public struct EnhanceSchedule: Sendable, Equatable {

    public struct Step: Sendable, Equatable {
        public let index: Int
        public let emitsPreview: Bool
        public let veilBlur: Double
    }

    public let plan: EnhancePlan
    public let steps: [Step]

    public init(plan: EnhancePlan = .standard) {
        self.plan = plan
        self.steps = (1...plan.totalSteps).map { index in
            Step(index: index,
                 emitsPreview: plan.emitsPreview(atStep: index),
                 veilBlur: plan.veilBlur(atStep: index))
        }
    }
}

/// How fast a mock run goes.
///
/// The default matches real hardware on purpose. A UI judgement made against an instant enhancer is
/// a judgement about a different app — the wait is the single biggest risk to how this one feels,
/// so the mock makes you sit through it.
public enum EnhanceSpeed: Sendable, Equatable {
    /// Tens of seconds, the window the handoff describes. Rolled per run so the UI is never tuned
    /// to one convenient duration.
    case device
    /// ~1 s. For iterating on the flow.
    case fast
    /// No waiting at all. For unit tests.
    case instant
    /// An exact per-step cost, for tests that assert on timing.
    case fixed(Duration)

    public func stepDuration() -> Duration {
        switch self {
        case .device:        return .milliseconds(Int.random(in: 700...1500))   // 14–30 s over 20
        case .fast:          return .milliseconds(50)
        case .instant:       return .zero
        case .fixed(let d):  return d
        }
    }
}
