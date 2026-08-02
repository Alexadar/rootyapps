//
//  WordData.swift
//  typingmill.swift
//
//  Created by Oleksandr Koreniuk on 20.09.2025.
//

import Foundation
import Combine

struct WordGroup: Codable {
    let chargroups: [String]
    let words: [String]
}

struct WordData: Codable {
    let groups: [WordGroup]
}

class TextGenerator: ObservableObject {
    private var wordData: WordData?
    private var currentDifficulty: Int = 1
    
    init() {
        loadWordData()
    }
    
    private func loadWordData() {
        guard let url = Bundle.main.url(forResource: "words_en", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("Failed to load words_en.json")
            return
        }
        
        do {
            wordData = try JSONDecoder().decode(WordData.self, from: data)
        } catch {
            print("Failed to decode word data: \(error)")
        }
    }
    
    func setDifficulty(_ difficulty: Int) {
        currentDifficulty = max(1, min(4, difficulty))
    }
    
    func getNextWord() -> String {
        guard let wordData = wordData,
              currentDifficulty <= wordData.groups.count else {
            return "test"
        }
        
        let group = wordData.groups[currentDifficulty - 1]
        let randomIndex = Int.random(in: 1..<group.words.count)
        return group.words[randomIndex]
    }
}
