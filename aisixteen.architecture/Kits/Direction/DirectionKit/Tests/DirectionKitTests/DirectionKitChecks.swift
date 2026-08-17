import Foundation
import Testing
@testable import DirectionKit

@Suite("Preset catalog")
struct PresetCatalogChecks {

    @Test("Exterior presets exist and are reachable")
    func exteriorIsReachable() {
        // The regression this suite exists for: `DirectionView` shipped
        // `let mode: SpaceMode = .interior`, a hardcoded constant, which made the entire exterior
        // list dead code nothing could reach. This is the dead-toggle class the house rule is
        // about — tests only ever saw the default state.
        #expect(PresetCatalog.presets(for: .exterior).count == 4)
        #expect(PresetCatalog.presets(for: .interior).count == 4)
        #expect(PresetCatalog.presets(for: .exterior).allSatisfy { $0.mode == .exterior })
        #expect(PresetCatalog.presets(for: .interior).allSatisfy { $0.mode == .interior })
    }

    @Test("Both modes are covered, in both directions")
    func bothModesResolve() {
        for mode in SpaceMode.allCases {
            let presets = PresetCatalog.presets(for: mode)
            #expect(!presets.isEmpty)
            #expect(PresetCatalog.first(for: mode).mode == mode)
        }
    }

    @Test("The design board's four exterior directions are all present")
    func boardExteriorsArePresent() {
        let names = PresetCatalog.exterior.map(\.name)
        #expect(names == ["Modern farmhouse", "Georgian", "Mediterranean", "Minimal render"])
    }

    @Test("Ids are unique across both modes")
    func idsAreUnique() {
        let ids = PresetCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every preset has a usable prompt, a name, a subtitle and four swatches")
    func everyPresetIsComplete() {
        for preset in PresetCatalog.all {
            #expect(!preset.prompt.isEmpty, "\(preset.id) has no prompt")
            #expect(!preset.name.isEmpty)
            #expect(!preset.sub.isEmpty)
            #expect(preset.swatchHexes.count == 4, "\(preset.id) has \(preset.swatchHexes.count) swatches")
            #expect(preset.swatchHexes.allSatisfy { $0 <= 0xFFFFFF })
        }
    }

    @Test("No prompt implies a measurement or a per-object edit")
    func promptsRespectTheScopeDecisions() {
        // Both capabilities were deliberately cut. No copy — including a prompt macro — may imply
        // segmentation ("just the sofa") or measuring.
        let forbidden = ["measure", "dimension", "square metre", "square meter",
                         "only the", "just the", "select the", "mask"]
        for preset in PresetCatalog.all {
            let prompt = preset.prompt.lowercased()
            for word in forbidden {
                #expect(!prompt.contains(word), "\(preset.id): \(preset.prompt)")
            }
        }
    }

    @Test("An unknown preset id resolves to nil rather than crashing")
    func unknownIdIsNil() {
        // A project synced from a newer build can name a preset this one has never heard of.
        #expect(PresetCatalog.preset(id: "brutalist") == nil)
        #expect(PresetCatalog.preset(id: "scandi")?.name == "Scandinavian")
    }
}

@Suite("Prompt composition")
struct PromptComposerChecks {

    let scandi = PresetCatalog.preset(id: "scandi")!
    let japandi = PresetCatalog.preset(id: "japandi")!

    @Test("Picking a preset seeds the prompt and is not an edit")
    func presetSeedsPrompt() {
        let recipe = PromptComposer.select(scandi)
        #expect(recipe.prompt == scandi.prompt)
        #expect(recipe.presetID == "scandi")
        #expect(!recipe.isEdited)
        #expect(recipe.isUsable)
    }

    @Test("Typing marks the recipe edited but keeps the preset highlighted")
    func editingMarksEdited() {
        // The user chose that direction and then refined it; they did not abandon it.
        var recipe = PromptComposer.select(scandi)
        recipe = PromptComposer.edit(recipe, to: scandi.prompt + ", darker floor")

        #expect(recipe.isEdited)
        #expect(recipe.presetID == "scandi")
    }

    @Test("Whitespace and case alone are not an edit")
    func trivialDifferencesAreNotEdits() {
        var recipe = PromptComposer.select(scandi)
        recipe = PromptComposer.edit(recipe, to: "  " + scandi.prompt.uppercased() + "  ")
        #expect(!recipe.isEdited)
    }

    @Test("Re-picking after an edit replaces the prompt and offers an undo")
    func repickReplacesAndOffersUndo() {
        var recipe = PromptComposer.select(scandi)
        recipe = PromptComposer.edit(recipe, to: "Bright Scandinavian living room with a green sofa")

        let (replaced, undo) = PromptComposer.repick(japandi, from: recipe)

        #expect(replaced.prompt == japandi.prompt)
        #expect(replaced.presetID == "japandi")
        #expect(!replaced.isEdited)
        // Silently discarding what someone typed is not acceptable; there is a way back.
        #expect(undo?.prompt == "Bright Scandinavian living room with a green sofa")
    }

    @Test("Re-picking an unedited prompt offers no undo")
    func repickWithoutEditHasNoUndo() {
        let recipe = PromptComposer.select(scandi)
        let (replaced, undo) = PromptComposer.repick(japandi, from: recipe)
        #expect(replaced.presetID == "japandi")
        #expect(undo == nil, "nothing was lost, so there is nothing to undo")
    }

    @Test("Each chip appends exactly once, however many times it is tapped")
    func chipsAppendOnce() {
        // The handoff's `prompt += ", " + chip.dropFirst(2)` produces
        // ", more plants, more plants" on a double tap.
        var recipe = PromptComposer.select(scandi)
        recipe = PromptComposer.append(.morePlants, to: recipe)
        let afterFirst = recipe.prompt
        recipe = PromptComposer.append(.morePlants, to: recipe)

        #expect(recipe.prompt == afterFirst)
        #expect(recipe.prompt.hasSuffix("more plants"))
        #expect(recipe.prompt.components(separatedBy: "more plants").count == 2)
    }

    @Test("A chip strips its plus sign and joins with a comma")
    func chipsJoinCleanly() {
        var recipe = PromptComposer.select(scandi)
        recipe = PromptComposer.append(.warmerLight, to: recipe)

        #expect(!recipe.prompt.contains("+"))
        #expect(recipe.prompt == scandi.prompt + ", warmer light")
        #expect(PromptChip.warmerLight.label == "+ warmer light")
    }

    @Test("A chip on an empty prompt does not start with a comma")
    func chipOnEmptyPrompt() {
        let empty = PromptRecipe(presetID: nil, prompt: "", mode: .interior)
        let appended = PromptComposer.append(.darkerFloor, to: empty)
        #expect(appended.prompt == "darker floor")
    }

    @Test("A chip after a trailing comma does not double it")
    func chipAfterTrailingComma() {
        let recipe = PromptRecipe(presetID: nil, prompt: "Bright room,", mode: .interior)
        let appended = PromptComposer.append(.morePlants, to: recipe)
        #expect(appended.prompt == "Bright room, more plants")
    }

    @Test("Used chips stop being offered, in both directions")
    func availableChipsShrinkAndRecover() {
        var recipe = PromptComposer.select(scandi)
        #expect(PromptComposer.availableChips(for: recipe).count == 3)

        recipe = PromptComposer.append(.morePlants, to: recipe)
        #expect(PromptComposer.availableChips(for: recipe) == [.warmerLight, .darkerFloor])

        // Delete the words again and the chip comes back.
        recipe = PromptComposer.edit(recipe, to: scandi.prompt)
        #expect(PromptComposer.availableChips(for: recipe).count == 3)
    }

    @Test("Changing mode swaps to that mode's presets when nothing was typed")
    func modeChangeSwapsPreset() {
        let interior = PromptComposer.select(scandi)
        let exterior = PromptComposer.changingMode(of: interior, to: .exterior)

        #expect(exterior.mode == .exterior)
        #expect(exterior.presetID == "farmhouse")
        #expect(exterior.prompt == PresetCatalog.first(for: .exterior).prompt)

        // And back again.
        let backToInterior = PromptComposer.changingMode(of: exterior, to: .interior)
        #expect(backToInterior.mode == .interior)
        #expect(backToInterior.presetID == "scandi")
    }

    @Test("Changing mode keeps words the user typed")
    func modeChangeKeepsTypedWords() {
        // Retyping a sentence because a segment was tapped is the worse failure.
        var recipe = PromptComposer.select(scandi)
        recipe = PromptComposer.edit(recipe, to: "A calm room with a lot of light and no clutter")

        let exterior = PromptComposer.changingMode(of: recipe, to: .exterior)
        #expect(exterior.prompt == "A calm room with a lot of light and no clutter")
        #expect(exterior.mode == .exterior)
        // The preset drops away — the interior sets and exterior sets are disjoint.
        #expect(exterior.presetID == nil)
    }

    @Test("Changing to the same mode is a no-op")
    func sameModeIsANoOp() {
        let recipe = PromptComposer.select(scandi)
        #expect(PromptComposer.changingMode(of: recipe, to: .interior) == recipe)
    }

    @Test("A recipe of only whitespace is not usable")
    func blankPromptIsNotUsable() {
        let blank = PromptRecipe(presetID: nil, prompt: "   \n  ", mode: .interior)
        #expect(!blank.isUsable)
        #expect(!blank.isEdited)
    }

    @Test("A recipe survives encoding")
    func recipeRoundTrips() throws {
        var recipe = PromptComposer.select(japandi)
        recipe = PromptComposer.append(.warmerLight, to: recipe)
        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(PromptRecipe.self, from: data)
        #expect(decoded == recipe)
        #expect(decoded.isEdited)
    }
}
