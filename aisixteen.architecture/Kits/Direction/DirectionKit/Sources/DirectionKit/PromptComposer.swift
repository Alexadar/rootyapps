import Foundation

/// The three one-tap additions under the prompt field, from the design handoff.
public enum PromptChip: String, CaseIterable, Sendable, Codable {
    case warmerLight = "warmer light"
    case morePlants = "more plants"
    case darkerFloor = "darker floor"

    /// What the chip reads on screen.
    public var label: String { "+ " + rawValue }
}

/// What the user actually asked for: a preset, possibly edited.
///
/// `isEdited` is not cosmetic. It is a named test axis, it decides whether re-picking a preset is
/// destructive, and it is stored on the project so "regenerate with edits" can reopen Direction
/// with the right words in the field.
public struct PromptRecipe: Equatable, Sendable, Codable, Hashable {
    public let presetID: String?
    public let prompt: String
    public let mode: SpaceMode

    public init(presetID: String?, prompt: String, mode: SpaceMode) {
        self.presetID = presetID
        self.prompt = prompt
        self.mode = mode
    }

    /// True when the words no longer match the preset that seeded them.
    public var isEdited: Bool {
        guard let presetID, let preset = PresetCatalog.preset(id: presetID) else {
            // Free text with no preset behind it is edited by definition — but whitespace is not
            // text, and an "edited" empty field would put a stale undo affordance on screen.
            return !PromptComposer.normalise(prompt).isEmpty
        }
        return PromptComposer.normalise(prompt) != PromptComposer.normalise(preset.prompt)
    }

    /// What the Result screen's "Try again" and the library's "Use this prompt again" carry.
    public var isUsable: Bool { !PromptComposer.normalise(prompt).isEmpty }
}

public enum PromptComposer {

    /// Picking a preset seeds the field. This is the whole "presets are prompt macros" mechanic.
    public static func select(_ preset: StylePreset) -> PromptRecipe {
        PromptRecipe(presetID: preset.id, prompt: preset.prompt, mode: preset.mode)
    }

    /// What happens when the user picks a different preset after typing.
    ///
    /// ⚠️ A decision the handoff does not make. `DirectionView` currently does
    /// `withAnimation { selected = p; prompt = p.prompt }` — an unconditional overwrite that
    /// silently throws away typed words.
    ///
    /// The choice here: a re-pick **does** replace the prompt, and returns the previous recipe so
    /// the UI can offer a one-line undo. Silently keeping stale text under a new preset name is
    /// worse (the card and the words disagree), and silently discarding what someone typed is
    /// worse still. Replacing visibly, with a way back, is the only option that is honest about
    /// what happened.
    public static func repick(_ preset: StylePreset,
                              from current: PromptRecipe) -> (recipe: PromptRecipe, undo: PromptRecipe?) {
        let replacement = select(preset)
        return (replacement, current.isEdited ? current : nil)
    }

    /// Typing. The preset id is kept so the card stays highlighted — the user chose that
    /// direction and then refined it; they did not abandon it.
    public static func edit(_ recipe: PromptRecipe, to prompt: String) -> PromptRecipe {
        PromptRecipe(presetID: recipe.presetID, prompt: prompt, mode: recipe.mode)
    }

    /// Append a chip, exactly once.
    ///
    /// Tapping "+ more plants" twice must not produce ", more plants, more plants" — the handoff's
    /// `prompt += ", " + chip.dropFirst(2)` would.
    public static func append(_ chip: PromptChip, to recipe: PromptRecipe) -> PromptRecipe {
        guard !contains(chip, in: recipe.prompt) else { return recipe }
        let trimmed = recipe.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined: String
        if trimmed.isEmpty {
            joined = chip.rawValue
        } else if trimmed.hasSuffix(",") {
            joined = trimmed + " " + chip.rawValue
        } else {
            joined = trimmed + ", " + chip.rawValue
        }
        return edit(recipe, to: joined)
    }

    public static func contains(_ chip: PromptChip, in prompt: String) -> Bool {
        normalise(prompt).contains(normalise(chip.rawValue))
    }

    /// Which chips are still worth offering.
    public static func availableChips(for recipe: PromptRecipe) -> [PromptChip] {
        PromptChip.allCases.filter { !contains($0, in: recipe.prompt) }
    }

    /// Collapse whitespace and case so "  Bright  Scandinavian " and "bright scandinavian" are the
    /// same words. Used for the edited check and for chip de-duplication — not for storage; what
    /// the user typed is stored verbatim.
    public static func normalise(_ string: String) -> String {
        string
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Switching Interior ↔ Exterior after the shot was taken.
    ///
    /// The preset sets are disjoint, so the old selection cannot survive. If the user had edited
    /// their prompt, their words are kept and the preset simply drops away — retyping a sentence
    /// because a segment was tapped would be the worse failure.
    public static func changingMode(of recipe: PromptRecipe, to mode: SpaceMode) -> PromptRecipe {
        guard recipe.mode != mode else { return recipe }
        if recipe.isEdited {
            return PromptRecipe(presetID: nil, prompt: recipe.prompt, mode: mode)
        }
        return select(PresetCatalog.first(for: mode))
    }
}
