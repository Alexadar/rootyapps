//
//  GameDataLoader.swift
//  bigpinkcat.swift Shared
//
//  Loads and manages game data from YAML files
//

import Foundation
import AVFoundation

class GameDataLoader {
    var gameMeta: GameMeta?
    var charactersRoot: CharactersRoot?
    var storySummary: StorySummary?
    var summaryParts: [Int: SummaryPart] = [:]
    var dialogs: [Int: [Dialog]] = [:]
    var dialogNodes: [Int: [DialogNode]] = [:]

    private let gameFolder: String

    init(gameFolder: String) {
        self.gameFolder = gameFolder
    }

    func loadAllData() throws {
        print("Loading game data for \(gameFolder)...")

        // Load metadata
        try loadMetadata()

        // Load characters
        try loadCharacters()

        // Note: Skipping story_summary - it has complex nested structure
        // and we don't actually use it (we use summary_parts directly)
        // try loadStorySummary()

        // Load all summary parts and dialogs
        try loadSummaryPartsAndDialogs()

        // Build dialog node tree
        buildDialogTree()

        print("Game data loaded successfully!")
    }

    private func loadMetadata() throws {
        print("Loading game metadata...")
        let metaPath = "output_story/game_meta"
        gameMeta = try YAMLParser.parse(metaPath)
        print("Game: \(gameMeta?.gameName ?? "Unknown")")
    }

    private func loadCharacters() throws {
        print("Loading characters...")

        // Use bundle resource URL to locate the YAML in the output_story subdirectory
        guard let bundle = Bundle.main.resourceURL else {
            throw NSError(domain: "GameDataLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not get bundle resource URL"])
        }

        let charactersURL = bundle.appendingPathComponent("output_story/characters_meta.yaml")
        let yamlString = try String(contentsOf: charactersURL, encoding: .utf8)

        // Parse YAML string directly to CharactersRoot
        let root: CharactersRoot = try YAMLParser.parseString(yamlString)
        charactersRoot = root

        print("Loaded \(charactersRoot?.characters.count ?? 0) characters")
    }

    private func loadStorySummary() throws {
        print("Loading story summary...")
        let summaryPath = "output_story/story_summary"
        storySummary = try YAMLParser.parse(summaryPath)
        print("Story summary loaded")
    }

    private func loadSummaryPartsAndDialogs() throws {
        print("Loading summary parts and dialogs...")

        // Load all YAML files from the summary_parts folder
        // Like Unity's Resources.LoadAll, we need to find all .yaml files
        guard let bundle = Bundle.main.resourceURL else {
            throw NSError(domain: "GameDataLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not get bundle resource URL"])
        }

        let summaryPartsURL = bundle.appendingPathComponent("output_story/summary_parts")

        guard let fileURLs = try? FileManager.default.contentsOfDirectory(at: summaryPartsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            print("Warning: Could not list files in summary_parts folder")
            return
        }

        // Filter for .yaml files only
        let yamlFiles = fileURLs.filter { $0.pathExtension == "yaml" }
        print("Found \(yamlFiles.count) summary part files")

        for fileURL in yamlFiles {
            do {
                // Load and parse the summary part YAML
                let yamlString = try String(contentsOf: fileURL, encoding: .utf8)
                let summaryPart: SummaryPart = try YAMLParser.parseString(yamlString)

                // Use the index field from the YAML to determine which dialog to load
                let index = summaryPart.index
                summaryParts[index] = summaryPart

                // Load corresponding dialog based on the index field
                let dialogPath = "output_story/dialogs/dialog_\(index)"
                let dialogArray: [Dialog] = try YAMLParser.parse(dialogPath)
                dialogs[index] = dialogArray

                print("Loaded summary part \(fileURL.lastPathComponent) (index: \(index)) with \(dialogArray.count) dialogs")
            } catch {
                print("Warning: Could not load summary part \(fileURL.lastPathComponent): \(error)")
            }
        }

        print("Successfully loaded \(summaryParts.count) summary parts")
    }

    private func buildDialogTree() {
        print("Building dialog tree...")

        guard let characters = charactersRoot else {
            print("Error: Characters not loaded")
            return
        }

        // Build dialog nodes for each summary part
        for (index, dialogArray) in dialogs {
            var nodes: [DialogNode] = []

            for (i, dialog) in dialogArray.enumerated() {
                guard let character = characters.findCharacter(id: dialog.characterId) else {
                    print("Warning: Character \(dialog.characterId) not found")
                    continue
                }

                let node = DialogNode(dialog: dialog, character: character)

                // Link to previous dialog robustly (use existing last node in case some dialogs were skipped)
                if let prev = nodes.last {
                    node.previousDialog = prev
                    prev.nextDialog = node
                }

                // Handle options for the last dialog
                if i == dialogArray.count - 1 {
                    if let options = dialog.options, !options.isEmpty {
                        if let summaryPart = summaryParts[index],
                           let nextStructsIdx = summaryPart.nextStructsIdx {
                            var optionsWithTargets: [DialogOptionWithTarget] = []
                            for (j, option) in options.enumerated() {
                                if j < nextStructsIdx.count {
                                    // nextStructsIdx entries may be strings like "Index 0".
                                    // Extract digits and convert to Int, fallback to 0 when conversion fails.
                                    let raw = nextStructsIdx[j]
                                    let digits = raw.compactMap { $0.wholeNumberValue }.map(String.init).joined()
                                    let targetIdx = Int(digits) ?? 0

                                    let optionWithTarget = DialogOptionWithTarget(
                                        text: option.optionText,
                                        nextSummaryIdx: targetIdx
                                    )
                                    optionsWithTargets.append(optionWithTarget)
                                }
                            }
                            node.options = optionsWithTargets
                        }
                    }
                }

                nodes.append(node)
            }

            dialogNodes[index] = nodes
        }

        print("Dialog tree built with \(dialogNodes.count) summary parts")
    }

    func getInitialDialog() -> DialogNode? {
        // Prefer summary index 0, but fall back to the first available summary part
        if let first = dialogNodes[0]?.first {
            return first
        }

        // If index 0 is missing (some summary parts failed to parse), return the first dialog of any loaded part
        if let anyFirst = dialogNodes.sorted(by: { $0.key < $1.key }).first?.value.first {
            return anyFirst
        }

        return nil
    }

    func getDialogForSummary(index: Int) -> DialogNode? {
        return dialogNodes[index]?.first
    }
}
