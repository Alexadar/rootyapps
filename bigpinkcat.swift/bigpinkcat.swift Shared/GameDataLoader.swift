//
//  GameDataLoader.swift
//  bigpinkcat.swift Shared
//
//  Loads and manages game data from YAML files
//

import Foundation
import AVFoundation
import Yams

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
        guard let url = Bundle.main.url(forResource: "game_meta", withExtension: "yaml", subdirectory: "output_story") else {
            throw NSError(domain: "GameDataLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "game_meta.yaml not found"])
        }
        let yamlString = try String(contentsOf: url, encoding: .utf8)
        let decoder = YAMLDecoder()
        gameMeta = try decoder.decode(GameMeta.self, from: yamlString)
        print("Game: \(gameMeta?.gameName ?? "Unknown")")
    }

    private func loadCharacters() throws {
        print("Loading characters...")
        guard let url = Bundle.main.url(forResource: "characters_meta", withExtension: "yaml", subdirectory: "output_story") else {
            throw NSError(domain: "GameDataLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "characters_meta.yaml not found"])
        }
        let yamlString = try String(contentsOf: url, encoding: .utf8)
        let decoder = YAMLDecoder()
        charactersRoot = try decoder.decode(CharactersRoot.self, from: yamlString)
        print("Loaded \(charactersRoot?.characters.count ?? 0) characters")
    }

    private func loadStorySummary() throws {
        print("Loading story summary...")
        guard let url = Bundle.main.url(forResource: "story_summary", withExtension: "yaml", subdirectory: "output_story") else {
            throw NSError(domain: "GameDataLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "story_summary.yaml not found"])
        }
        let yamlString = try String(contentsOf: url, encoding: .utf8)
        let decoder = YAMLDecoder()
        storySummary = try decoder.decode(StorySummary.self, from: yamlString)
        print("Story summary loaded")
    }

    private func loadSummaryPartsAndDialogs() throws {
        print("Loading summary parts and dialogs...")

        // Load all YAML files from the summary_parts folder
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

        let decoder = YAMLDecoder()

        for fileURL in yamlFiles {
            do {
                // Load and parse the summary part YAML
                let yamlString = try String(contentsOf: fileURL, encoding: .utf8)
                let summaryPart = try decoder.decode(SummaryPart.self, from: yamlString)

                // Use the index field from the YAML to determine which dialog to load
                let index = summaryPart.index
                summaryParts[index] = summaryPart

                // Load corresponding dialog based on the index field
                guard let dialogURL = Bundle.main.url(forResource: "dialog_\(index)", withExtension: "yaml", subdirectory: "output_story/dialogs") else {
                    print("Warning: dialog_\(index).yaml not found")
                    continue
                }
                let dialogYaml = try String(contentsOf: dialogURL, encoding: .utf8)
                let dialogArray = try decoder.decode([Dialog].self, from: dialogYaml)
                dialogs[index] = dialogArray

                // Debug: Check if last dialog has options
                if let lastDialog = dialogArray.last {
                    print("Loaded summary part \(fileURL.lastPathComponent) (index: \(index)) with \(dialogArray.count) dialogs, last dialog id=\(lastDialog.id), options=\(lastDialog.options?.count ?? 0)")
                } else {
                    print("Loaded summary part \(fileURL.lastPathComponent) (index: \(index)) with \(dialogArray.count) dialogs")
                }
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
                    print("DEBUG: Last dialog in summary \(index): id=\(dialog.id), options=\(String(describing: dialog.options)), optionsCount=\(dialog.options?.count ?? 0)")
                    if let options = dialog.options, !options.isEmpty {
                        print("DEBUG: Dialog \(dialog.id) has \(options.count) options: \(options.map { $0.optionText })")
                        if let summaryPart = summaryParts[index],
                           let nextStructsIdx = summaryPart.nextStructsIdx {
                            print("DEBUG: Summary part \(index) has nextStructsIdx: \(nextStructsIdx)")
                            var optionsWithTargets: [DialogOptionWithTarget] = []
                            for (j, option) in options.enumerated() {
                                if j < nextStructsIdx.count {
                                    let targetIdx = nextStructsIdx[j]
                                    let optionWithTarget = DialogOptionWithTarget(
                                        text: option.optionText,
                                        nextSummaryIdx: targetIdx
                                    )
                                    optionsWithTargets.append(optionWithTarget)
                                    print("DEBUG: Option \(j): '\(option.optionText)' -> summary \(targetIdx)")
                                }
                            }
                            node.options = optionsWithTargets
                            print("Added \(optionsWithTargets.count) options to dialog \(index), last dialog id \(dialog.id)")
                        } else {
                            print("Warning: No nextStructsIdx found for summary part \(index). summaryPart exists: \(summaryParts[index] != nil), nextStructsIdx: \(String(describing: summaryParts[index]?.nextStructsIdx))")
                        }
                    } else {
                        print("DEBUG: No options found in last dialog \(dialog.id)")
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
