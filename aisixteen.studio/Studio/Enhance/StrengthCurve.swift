import Foundation
import RecipeKit
import DiffusionRuntime

/// Maps the design's 0–100 rail onto the model's denoise fraction.
///
/// ### The detent number is a label, not a denoise fraction
///
/// Dividing by 100 would be the obvious thing and it is wrong twice over.
///
/// **It alters faces.** Measured on the wallpaper app: 0.35 invents texture, which is right for a
/// generated picture and wrong for someone's photo of their kid. The handoff's own descriptions are
/// the specification — Whisper is "pixel-faithful", Subtle leaves "faces untouched in structure" —
/// and 0.15 / 0.35 cannot deliver those claims. The anchors below can.
///
/// **It crashes.** `Scheduler.addNoise` indexes `timeSteps[steps - Int(steps × strength)]`, so any
/// strength where `steps × strength` floors to zero indexes one past the end of the array and takes
/// the process with it. At `steps: 12` that is every denoise below 0.0834 — which a linear mapping
/// reaches from **16 of 100 rail positions**, including Whisper. `clamped` is the floor, and it is
/// applied to every value on the rail rather than to the four named ones, because the user can put
/// the handle anywhere and the detents are only labels on it.
enum StrengthCurve {

    /// Nominal denoising steps per tile.
    ///
    /// ⚠️ **This number sets how many distinct pictures the dial can produce.** The schedule runs
    /// `Int(steps × strength)` steps, so a rail capped at 0.5 resolves to `steps / 2` outcomes —
    /// **6 at twelve**, whatever the rail's length. Twelve matches the wallpaper app (~42 s for a
    /// 12-tile photo); twenty-four doubles the resolution to 12 outcomes and roughly doubles the
    /// wait. Twelve is the default because the shorter wait is the safer starting point for an app
    /// whose verb is *enhance*; the owner has not chosen yet.
    static let steps = 12

    /// The top of the rail. Deliberately **not** 1.0 — above ~0.5 the pass stops enhancing a photo
    /// and starts replacing it, which is Architecture's job, not this app's.
    static let maximumDenoise: Float = 0.5

    /// Rail position → denoise, piecewise-linear through the four detents.
    ///
    /// Anchored so each detent earns the claim printed under it in the interface.
    private static let anchors: [(rail: Double, denoise: Float)] = [
        (0, 0.0),
        (Detent.whisper.rawValue, 0.10),    // 15 — pixel-faithful
        (Detent.subtle.rawValue, 0.18),     // 35 — faces untouched in structure
        (Detent.balanced.rawValue, 0.28),   // 55 — reconstructs detail, same shot
        (Detent.strong.rawValue, 0.42),     // 80 — full re-render, warned in-line
        (100, maximumDenoise),
    ]

    /// The value handed to the pass. **Always safe** — floored at the step count's minimum.
    ///
    /// Zero is the one input with no denoise at all: the interface refuses Enhance there
    /// (`EditModel.canEnhance`), because at zero the answer is the original and running a model to
    /// produce it would be theatre.
    static func denoise(for strength: Strength, steps: Int = steps) -> Float? {
        guard !strength.isZero else { return nil }
        return TiledControlNetPass.clamped(strength: interpolated(strength.value), forSteps: steps)
    }

    private static func interpolated(_ rail: Double) -> Float {
        let clamped = min(max(rail, 0), 100)
        for (low, high) in zip(anchors, anchors.dropFirst()) where clamped <= high.rail {
            let span = high.rail - low.rail
            guard span > 0 else { return high.denoise }
            let t = Float((clamped - low.rail) / span)
            return low.denoise + (high.denoise - low.denoise) * t
        }
        return maximumDenoise
    }

    /// How many genuinely different pictures the rail can produce for a given step count.
    ///
    /// Comes from the base rather than being recomputed here, so it cannot drift from what the
    /// scheduler will actually do.
    static func distinctOutcomes(forSteps steps: Int = steps) -> Int {
        TiledControlNetPass.distinctOutcomes(forSteps: steps,
                                             strengthFrom: 0,
                                             to: maximumDenoise)
    }
}
