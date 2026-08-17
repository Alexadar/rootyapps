import Foundation
import SwiftUI
import PromptKit

/// The controls the design deliberately keeps off the main screen.
///
/// The app's position is calm and uncluttered — "the absence of noise *is* the product" — so none of
/// this belongs on Create. It lives behind one disclosure, defaults to values that work, and is
/// persisted so a user who tunes it once is not asked again.
///
/// It is **not a third screen**: a sheet over Create, dismissable, with nothing in it that has to be
/// understood in order to make a wallpaper.
@MainActor
@Observable
final class AdvancedSettings {

    /// What the model should avoid. Defaults to the wallpaper-tuned list, not the character-art one
    /// everybody copies — see `NegativePrompt`.
    var negativePrompt: String {
        didSet { defaults.set(negativePrompt, forKey: Keys.negative) }
    }

    /// Stage 1 — diffusion. Past roughly 30 the picture stops changing and only the wait grows;
    /// below about 15 the composition has not settled.
    var generationSteps: Int {
        didSet { defaults.set(generationSteps, forKey: Keys.generationSteps) }
    }

    /// Stage 3 — tile refine. Nominal: at strength 0.35 only about a third actually run, because
    /// image-to-image skips the early part of the schedule.
    var refineSteps: Int {
        didSet { defaults.set(refineSteps, forKey: Keys.refineSteps) }
    }

    /// How far each tile is allowed to depart from what is already there. Higher invents objects
    /// that were not in the picture, and neighbouring tiles then disagree about what it contains.
    var refineStrength: Double {
        didSet { defaults.set(refineStrength, forKey: Keys.refineStrength) }
    }

    /// Stage 2 — the upscale. Off makes a smaller, faster wallpaper rather than a broken one.
    var upscaleEnabled: Bool {
        didSet { defaults.set(upscaleEnabled, forKey: Keys.upscale) }
    }

    var guidanceScale: Double {
        didSet { defaults.set(guidanceScale, forKey: Keys.guidance) }
    }

    static let generationStepRange = 12...40
    static let refineStepRange = 6...20

    private let defaults: UserDefaults

    private enum Keys {
        static let negative = "wp.advanced.negativePrompt"
        static let generationSteps = "wp.advanced.generationSteps"
        static let refineSteps = "wp.advanced.refineSteps"
        static let refineStrength = "wp.advanced.refineStrength"
        static let upscale = "wp.advanced.upscale"
        static let guidance = "wp.advanced.guidance"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        negativePrompt = defaults.string(forKey: Keys.negative) ?? NegativePrompt.wallpaperDefault
        generationSteps = defaults.object(forKey: Keys.generationSteps) as? Int ?? 28
        refineSteps = defaults.object(forKey: Keys.refineSteps) as? Int ?? 12
        refineStrength = defaults.object(forKey: Keys.refineStrength) as? Double ?? 0.35
        upscaleEnabled = defaults.object(forKey: Keys.upscale) as? Bool ?? true
        guidanceScale = defaults.object(forKey: Keys.guidance) as? Double ?? 7.5
    }

    // MARK: Token budget

    var negativeTokenEstimate: Int { NegativePrompt.estimatedTokens(negativePrompt) }
    var negativeIsWithinLimit: Bool { NegativePrompt.isWithinLimit(negativePrompt) }

    /// Said plainly, because the failure is silent: CLIP drops the tail and the user never learns
    /// that half of what they typed did nothing.
    var negativeBudgetText: String {
        "\(negativeTokenEstimate) of \(NegativePrompt.tokenLimit) tokens"
            + (negativeIsWithinLimit ? "" : " — the end will be ignored")
    }

    func resetNegativeToDefault() { negativePrompt = NegativePrompt.wallpaperDefault }
    func useFigurativeNegative() { negativePrompt = NegativePrompt.figurative }
}
