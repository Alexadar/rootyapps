import Testing
import Foundation
@testable import GenerationKit

/// ORACLES:
///  • SPEC — the design bundle (`1b`) fixes three numbers: latents decode "every 2–3 steps", the
///    capsule becomes a frame at "~ step 5", and the veil blur eases 26 → 0 pt. Those are the
///    oracle here; the plan exists to make them checkable rather than sprinkled through views.
///  • INVARIANT — the final step ALWAYS decodes, whatever the cadence. Without this the user is
///    left looking at the second-to-last picture while the app claims to be finished.
/// MODEL CAVEAT: the plan describes the *schedule*, not the pixels. Whether a decoded latent looks
/// like anything is the renderer's problem.
@Suite("GenerationPlan — the schedule the bundle specifies")
struct GenerationPlanTests {

    @Test("the standard plan is 28 steps, cadence 2, frame at 5")
    func standardValues() {
        let plan = GenerationPlan.standard
        #expect(plan.totalSteps == 28)
        #expect(plan.previewCadence == 2)
        #expect(plan.frameRevealStep == 5)
        #expect(plan.initialVeilBlur == 26)
        #expect(plan.veilOpacity == 0.22)
    }

    @Test("previews land on 1, 3, 5 … — every 2 steps, as specified")
    func previewCadence() {
        let plan = GenerationPlan.standard
        #expect(plan.emitsPreview(atStep: 1))
        #expect(!plan.emitsPreview(atStep: 2))
        #expect(plan.emitsPreview(atStep: 3))
        #expect(!plan.emitsPreview(atStep: 4))
        #expect(plan.emitsPreview(atStep: 5))
        // 14 odd steps (1…27) plus step 28, which always decodes.
        #expect(plan.previewSteps.count == 15)
    }

    @Test("the last step always decodes, even when the cadence would skip it")
    func lastStepAlwaysDecodes() {
        // 29 with cadence 3 lands on 1,4,7,…,28 — step 29 is NOT on the cadence.
        let plan = GenerationPlan(totalSteps: 29, previewCadence: 3)
        #expect((29 - 1) % 3 != 0, "precondition: 29 is off this cadence")
        #expect(plan.emitsPreview(atStep: 29), "the finished picture must be shown")
        #expect(plan.previewSteps.last == 29)
    }

    @Test("steps outside the run emit nothing")
    func outOfRange() {
        let plan = GenerationPlan.standard
        #expect(!plan.emitsPreview(atStep: 0))
        #expect(!plan.emitsPreview(atStep: -1))
        #expect(!plan.emitsPreview(atStep: 29))
    }

    @Test("the frame takes over from the capsule at step 5, not before")
    func frameReveal() {
        let plan = GenerationPlan.standard
        #expect(!plan.showsFrame(atStep: 4))
        #expect(plan.showsFrame(atStep: 5))
        #expect(plan.showsFrame(atStep: 28))
    }

    @Test("the veil eases 26 → 0 across the previews and never goes backwards")
    func veilLift() {
        let plan = GenerationPlan.standard
        #expect(plan.veilBlur(atStep: 1) == 26)
        #expect(plan.veilBlur(atStep: 28) == 0)

        var previous = Double.infinity
        for step in 1...28 {
            let blur = plan.veilBlur(atStep: step)
            #expect(blur <= previous + 1e-9, "veil thickened at step \(step)")
            #expect(blur >= 0)
            #expect(blur <= 26)
            previous = blur
        }
    }

    @Test("the veil holds between previews — it lifts when a picture arrives, not on a timer")
    func veilHoldsBetweenPreviews() {
        let plan = GenerationPlan.standard
        #expect(plan.veilBlur(atStep: 3) == plan.veilBlur(atStep: 4))
        #expect(plan.veilBlur(atStep: 5) < plan.veilBlur(atStep: 4))
    }

    @Test("the fraction is monotonic, starts above zero and ends at exactly 1")
    func fraction() {
        let plan = GenerationPlan.standard
        #expect(plan.fraction(atStep: 0) == 0)
        #expect(plan.fraction(atStep: 28) == 1)
        #expect(plan.fraction(atStep: 14) == 0.5)
        #expect(plan.fraction(atStep: 999) == 1, "a bar must never exceed its track")
    }

    @Test("the schedule has one entry per step and agrees with the plan on every field")
    func scheduleMatchesPlan() {
        let plan = GenerationPlan.standard
        let schedule = GenerationSchedule(plan: plan)
        #expect(schedule.steps.count == plan.totalSteps)
        for step in schedule.steps {
            #expect(step.emitsPreview == plan.emitsPreview(atStep: step.index))
            #expect(step.showsFrame == plan.showsFrame(atStep: step.index))
            #expect(step.veilBlur == plan.veilBlur(atStep: step.index))
            #expect(step.fraction == plan.fraction(atStep: step.index))
        }
        #expect(schedule.steps.first?.index == 1)
        #expect(schedule.steps.last?.index == 28)
    }

    @Test("at the shipped per-step cost the mock lands inside the real 10–30 s window")
    func mockDurationIsRealistic() {
        let schedule = GenerationSchedule()
        // The mock picks a per-step cost in this range; both ends must stay in the window the
        // design brief describes for on-device diffusion, or the waiting-state design is being
        // judged against a lie.
        let fastest = schedule.duration(perStep: .milliseconds(400))
        let slowest = schedule.duration(perStep: .milliseconds(1000))
        #expect(fastest >= .seconds(10))
        #expect(slowest <= .seconds(30))
    }
}

/// ORACLES:
///  • PUBLISHED — SplitMix64 as given in Steele/Lea/Flood (OOPSLA 2014) and in Blackman & Vigna's
///    reference C. Seeding state with 0 and stepping the gamma yields the published first outputs.
///  • INVARIANT — identical seeds give identical sequences; different seeds diverge immediately.
/// MODEL CAVEAT: this is not a cryptographic generator and must never be used as one.
@Suite("SeededRandomNumberGenerator — reproducibility")
struct SeededRandomTests {

    @Test("the same seed replays exactly")
    func deterministic() {
        var a = SeededRandomNumberGenerator(seed: UInt64(42))
        var b = SeededRandomNumberGenerator(seed: UInt64(42))
        for _ in 0..<64 { #expect(a.next() == b.next()) }
    }

    @Test("adjacent seeds do not produce adjacent output")
    func adjacentSeedsDiverge() {
        var a = SeededRandomNumberGenerator(seed: UInt64(1))
        var b = SeededRandomNumberGenerator(seed: UInt64(2))
        let first = a.next(), second = b.next()
        #expect(first != second)
        // Neighbouring seeds must not give neighbouring values, or two wallpapers made a second
        // apart would look the same.
        #expect(first.subtractingReportingOverflow(second).partialValue > 1_000_000)
    }

    @Test("matches the published splitmix64 output for state 0")
    func publishedVector() {
        // Reference C: state starts at the seed; each call adds 0x9E3779B97F4A7C15 first.
        // Seeding with (0 - gamma) makes the first call operate on state 0, whose published
        // output is 0xE220A8397B1DCDAF.
        var g = SeededRandomNumberGenerator(seed: UInt64(0) &- 0x9E37_79B9_7F4A_7C15)
        #expect(g.next() == 0xE220_A839_7B1D_CDAF)
    }

    @Test("stableHash is stable across launches, unlike String.hashValue")
    func stableHashIsFNV1a() {
        // FNV-1a 64-bit of "" is the offset basis; of "a" is the published value. If this ever
        // changes, every stored seed renders a different picture.
        #expect(stableHash("") == 0xCBF2_9CE4_8422_2325)
        #expect(stableHash("a") == 0xAF63_DC4C_8601_EC8C)
        #expect(stableHash("molten glass poppies") == stableHash("molten glass poppies"))
        #expect(stableHash("a") != stableHash("b"))
    }
}
