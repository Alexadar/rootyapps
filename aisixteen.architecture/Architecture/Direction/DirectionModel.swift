import DirectionKit
import Foundation
import FormatKit
import Observation
import RedesignKit

/// The Direction screen's state.
///
/// ⚠️ The handoff's `DirectionView` declared `let mode: SpaceMode = .interior` — a hardcoded
/// constant. `StylePreset.exterior` was therefore dead code that nothing in the app could reach,
/// which is exactly the class of bug the house "test the state space" rule exists for. Here `mode`
/// comes from the shot the user actually took.
@MainActor
@Observable
final class DirectionModel {

    let shot: SourceShot
    private(set) var recipe: PromptRecipe
    /// Set when a preset re-pick replaced typed words, so the UI can offer one line of undo.
    private(set) var undo: PromptRecipe?
    var variations: Int = 3

    /// Seconds per variation, measured. Nil until a render has actually been timed, at which point
    /// the CTA uses the seeded figure and says "about".
    var measuredSecondsPerVariation: TimeInterval?

    init(shot: SourceShot) {
        self.shot = shot
        let mode: DirectionKit.SpaceMode = shot.mode == .interior ? .interior : .exterior
        self.recipe = PromptComposer.select(PresetCatalog.first(for: mode))
    }

    /// Re-open Direction on an existing project — "Regenerate with edits".
    init(shot: SourceShot, recipe: PromptRecipe, variations: Int) {
        self.shot = shot
        self.recipe = recipe
        self.variations = variations
    }

    var mode: DirectionKit.SpaceMode { shot.mode == .interior ? .interior : .exterior }
    var presets: [StylePreset] { PresetCatalog.presets(for: mode) }
    var selectedPresetID: String? { recipe.presetID }
    var prompt: String { recipe.prompt }
    var availableChips: [PromptChip] { PromptComposer.availableChips(for: recipe) }

    /// The depth badge. Three strings, not one, because the three sources are not equally good and
    /// claiming otherwise is the sort of small lie this design is built to avoid.
    var depthBadge: String {
        shot.hasDepth ? shot.provenance.badgeText : "No depth — geometry may shift"
    }

    var depthIsMeasured: Bool { shot.hasDepth && shot.provenance.isMeasured }

    // ── editing ──────────────────────────────────────────────────────────────────────────────

    func select(_ preset: StylePreset) {
        let (next, undo) = PromptComposer.repick(preset, from: recipe)
        recipe = next
        self.undo = undo
    }

    func edit(_ prompt: String) {
        recipe = PromptComposer.edit(recipe, to: prompt)
        undo = nil
    }

    func append(_ chip: PromptChip) {
        recipe = PromptComposer.append(chip, to: recipe)
    }

    func undoRepick() {
        guard let undo else { return }
        recipe = undo
        self.undo = nil
    }

    // ── the CTA ──────────────────────────────────────────────────────────────────────────────

    /// The seeded figure, until a real run has been measured.
    ///
    /// The handoff hardcoded `minutesPerVariation = 2`. Keeping a seeded number is right — the CTA
    /// has to say something before anything has ever been rendered — but it must be replaced by
    /// the measurement as soon as one exists, and it must never be presented as one.
    static let seededSecondsPerVariation: TimeInterval = 120

    var secondsPerVariation: TimeInterval {
        measuredSecondsPerVariation ?? Self.seededSecondsPerVariation
    }

    var ctaTitle: String {
        "Redesign · " + DurationText.total(variations: variations,
                                           minutesEach: secondsPerVariation / 60)
    }

    var eachLine: String {
        DurationText.each(minutes: secondsPerVariation / 60) + " · run one after another"
    }

    var variationLine: String { VariationText.count(variations) }

    var canStart: Bool { recipe.isUsable }
}
