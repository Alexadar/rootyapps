import Foundation
import CoreGraphics

/// **The seam between the app and the model.**
///
/// Today every implementation is a mock. When the real pipeline arrives it conforms to this and
/// nothing above it changes — that is the entire point, and `EnhancerFactory` in the app is the one
/// place that knows which implementation exists.
///
/// ### Why `strength` and `mask` are here before anything uses them
///
/// The mocks ignore both. They are in the signature anyway because they are *the product*: strength
/// is a denoise fraction to a real diffusion model — 15 and 80 are genuinely different renders, not
/// two opacities of one render — and the mask is what makes "subject only" mean anything. A seam
/// that grew them later would be a seam that reshaped the UI later.
public protocol PhotoEnhancer: AnyObject {

    /// - Parameters:
    ///   - photo: the decoded original. **Never written to.**
    ///   - strength: 0–100, the value under the user's thumb. Not a 0–1 fraction — the design, the
    ///     recipe and the model all speak the same number.
    ///   - mask: white where the pass applies. `nil` means the whole frame.
    ///   - seed: `nil` rolls a new one; the chosen seed comes back on `EnhancedPhoto` so the pass
    ///     can be reproduced exactly.
    ///   - progress: called on every step, from any thread.
    func enhance(photo: CGImage,
                 strength: Double,
                 mask: CGImage?,
                 seed: UInt32?,
                 progress: @escaping (EnhanceProgress) -> Void) async throws -> EnhancedPhoto

    /// Stops the run between steps.
    ///
    /// ⚠️ This exists **alongside** task cancellation, not instead of it. A real pipeline spends
    /// each step inside a single non-cancellable Core ML prediction call; a flag checked between
    /// steps is the only thing that can actually stop it, and callers must be able to use either
    /// door. Both produce `EnhanceError.cancelled`.
    func cancel()

    /// How many steps this enhancer takes and how its veil lifts. The UI reads it so the progress
    /// capsule can say "step 9 of 20" before the first step has run.
    var plan: EnhancePlan { get }
}

/// One step's worth of news.
///
/// ⚠️ **Never a 0–1 float.** The design is explicit that the wait is reported as steps and not as a
/// percentage, and a type that carries a fraction is a type that invites a percentage back into the
/// label. The fraction for the capsule's fill is derived from these two integers, in one place.
public struct EnhanceProgress: Sendable, Equatable {

    /// 1-based, so `step` and `totalSteps` read the way the label does.
    public let step: Int
    public let totalSteps: Int
    /// The image as it stands, at a reduced scale. `nil` on steps that decode nothing.
    public let intermediate: CGImage?

    public init(step: Int, totalSteps: Int, intermediate: CGImage? = nil) {
        self.step = step
        self.totalSteps = totalSteps
        self.intermediate = intermediate
    }

    /// "Enhancing · step 9 of 20" — the handoff's wording, built in one place so no view spells it.
    public var label: String { "Enhancing · step \(step) of \(totalSteps)" }

    /// The capsule's fill width. The **only** legitimate fraction in the whole flow.
    public var fillFraction: Double {
        guard totalSteps > 0 else { return 0 }
        return min(1, max(0, Double(step) / Double(totalSteps)))
    }

    public static func == (lhs: EnhanceProgress, rhs: EnhanceProgress) -> Bool {
        lhs.step == rhs.step
            && lhs.totalSteps == rhs.totalSteps
            && (lhs.intermediate == nil) == (rhs.intermediate == nil)
    }
}

/// What a finished pass hands back.
///
/// It carries the strength it *actually rendered at* because that is not always the strength that
/// was asked for — and because the recipe needs it to know how far the dial can be backed off
/// without another pass.
public struct EnhancedPhoto {
    public let image: CGImage
    /// 0–100. The recipe stores this as `rendered`.
    public let renderedStrength: Double
    public let seed: UInt32
    public let steps: Int

    public init(image: CGImage, renderedStrength: Double, seed: UInt32, steps: Int) {
        self.image = image
        self.renderedStrength = renderedStrength
        self.seed = seed
        self.steps = steps
    }
}

/// Everything that can stop a pass.
///
/// `cancelled` is deliberately not an error the UI shows: a user who stopped it was not shown a
/// failure and must not be.
public enum EnhanceError: Error, Equatable, Sendable {
    case cancelled
    case outOfMemory
    case unsupportedImage
    case failed(reason: String)

    /// The sentence the failure card shows. `cancelled` has none, on purpose.
    public var displayReason: String? {
        switch self {
        case .cancelled:
            return nil
        case .outOfMemory:
            return "This photo needed more memory than was free. Closing other apps usually fixes it."
        case .unsupportedImage:
            return "That file isn't an image this app can open."
        case .failed(let reason):
            return reason
        }
    }

    /// The failure card's heading and its reassurance (`1c` failure state).
    public static let failureHeading = "That one didn't come together"
    public static let failureReassurance = "Nothing was lost — your photo is exactly as it was."
}

extension UInt32 {
    /// A fresh seed. Never zero, so "no seed" and "seed 0" can never be confused in a stored recipe.
    public static func randomSeed() -> UInt32 { UInt32.random(in: 1...UInt32.max) }
}
