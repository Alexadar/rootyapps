import Foundation

/// Where each foot is, at a given point in the walk.
///
/// In `Engine/` rather than in the renderer, for the same reason the wobble spring is: it is feel
/// maths, and feel maths in a renderer cannot be tested. The property that matters here — **a planted
/// foot does not move** — is arithmetic, and arithmetic can be proved rather than squinted at.
///
/// The gait is a **lateral-sequence walk**: rear-left, front-left, rear-right, front-right, a quarter
/// cycle apart. That is what a pig uses. The first version ran a diagonal trot, which is a running
/// gait, and it read as a bouncing toy.
struct WalkCycle {

    /// Metres of travel per full cycle of one leg. This is the stride, and it is the same number the
    /// engine advances `gait` with — `2π / cadence`.
    let stride: Double
    /// Fraction of the cycle a foot spends on the ground. Above a half by definition for a walk.
    let duty: Double

    init(stride: Double, duty: Double) {
        self.stride = stride
        self.duty = duty
    }

    init(fat: Double, in c: WorldConfig) {
        self.init(stride: c.stride(atFat: fat), duty: c.dutyFactor)
    }

    /// Quarter-cycle offsets, in the order the feet actually leave the ground.
    static let phaseOffsets: [Double] = [0, 0.25, 0.5, 0.75]

    /// How far forward of its hip the foot is, and how far off the ground, at `phase` in 0…1.
    ///
    /// **Stance is a straight line, and that is the whole trick.** The body advances `stride × duty`
    /// while a foot is down, so the foot must travel exactly that far backwards through the body's
    /// own frame to stay where it was put. Anything else — a sine, a smoothed ease, an amplitude
    /// picked by eye — and the foot slides by the difference, which is what "skating" is.
    func foot(at phase: Double) -> (reach: Double, lift: Double) {
        let p = phase - floor(phase)
        let half = stride * duty * 0.5
        if p < duty {
            return (half - 2 * half * (p / duty), 0)
        }
        let t = (p - duty) / (1 - duty)
        return (-half + 2 * half * t, sin(Double.pi * t))
    }

    /// Where a planted foot sits in the world, given how far the pig has walked.
    ///
    /// Constant through the whole stance if the cycle is honest — which is exactly what
    /// `WalkCycleTests` asserts, and the only way to check planting without watching it.
    func worldFoot(travelled: Double) -> Double {
        let phase = travelled / stride
        return travelled + foot(at: phase).reach
    }
}
