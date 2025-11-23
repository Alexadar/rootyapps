//
//  GameDataModels.swift
//  bigpinkcat.swift Shared
//
//  Visual novel data models ported from Unity C# version
//

import Foundation
import AVKit

// MARK: - Game Meta
struct GameMeta: Codable {
    let gameName: String
    let plotSummary: String

    enum CodingKeys: String, CodingKey {
        case gameName = "game_name"
        case plotSummary = "plot_summary"
    }
}

// MARK: - Character
struct Character: Codable {
    let id: Int
    let name: String
    let description: String

    // Runtime properties (not in YAML)
    var videoName: String? {
        return "char\(id)/latest_u_d"
    }
}

struct CharactersRoot: Codable {
    let characters: [Character]

    func findCharacter(id: Int) -> Character? {
        return characters.first { $0.id == id }
    }
}

// MARK: - Dialog
struct Dialog: Codable {
    let id: Int
    let characterId: Int
    let characterName: String
    let characterText: String
    let options: [DialogOption]?
    let finalWordsOfTheStory: String?

    enum CodingKeys: String, CodingKey {
        case id
        case characterId = "character_id"
        case characterName = "character_name"
        case characterText = "character_text"
        case options
        case finalWordsOfTheStory = "final_words_of_the_story"
    }
}

struct DialogOption: Codable {
    let optionText: String
    var nextSummaryIdx: Int = 0  // Set at runtime

    enum CodingKeys: String, CodingKey {
        case optionText = "option_text"
    }
}

// MARK: - Story Summary
struct StorySummary: Codable {
    let index: Int
    let currentOption: String?
    let currentSummary: String
    let previousStructure: String?
    let previousSummary: String?
    let nextStructs: [StorySummary]?

    enum CodingKeys: String, CodingKey {
        case index
        case currentOption = "current_option"
        case currentSummary = "current_summary"
        case previousStructure = "previous_structure"
        case previousSummary = "previous_summary"
        case nextStructs = "next_structs"
    }
}

// MARK: - Summary Part
struct SummaryPart: Codable {
    let index: Int
    let currentOption: String?
    let currentSummary: String
    let previousStructure: String?
    let previousSummary: String?
    let nextOptions: [String]?
    let nextStructs: [String]?
    // next_structs_idx can be integers or strings - we store as Int array
    let nextStructsIdx: [Int]?

    enum CodingKeys: String, CodingKey {
        case index
        case currentOption = "current_option"
        case currentSummary = "current_summary"
        case previousStructure = "previous_structure"
        case previousSummary = "previous_summary"
        case nextOptions = "next_options"
        case nextStructs = "next_structs"
        case nextStructsIdx = "next_structs_idx"
    }
}

// MARK: - Dialog with Navigation
class DialogNode {
    let dialog: Dialog
    let character: Character
    var nextDialog: DialogNode?
    var previousDialog: DialogNode?
    var options: [DialogOptionWithTarget]?

    init(dialog: Dialog, character: Character) {
        self.dialog = dialog
        self.character = character
    }
}

struct DialogOptionWithTarget {
    let text: String
    let nextSummaryIdx: Int
}
