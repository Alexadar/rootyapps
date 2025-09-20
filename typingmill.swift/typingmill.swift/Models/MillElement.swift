//
//  MillElement.swift
//  typingmill.swift
//
//  Created by Oleksandr Koreniuk on 20.09.2025.
//

import Foundation
import SwiftUI
import Combine

enum MillElementType {
    case word
    case space
}

class MillElement: ObservableObject, Identifiable {
    let id = UUID()
    let type: MillElementType
    @Published var text: String = ""
    @Published var doneText: String = ""
    @Published var notDoneText: String = ""
    @Published var isCurrent: Bool = false
    @Published var isCompleted: Bool = false
    @Published var isFadedOut: Bool = false
    
    private var donePosition: Int = 0
    
    init(type: MillElementType, text: String = "") {
        self.type = type
        self.text = text
        self.notDoneText = text
        self.doneText = ""
    }
    
    var currentChar: Character {
        if type == .space {
            return " "
        }
        guard donePosition < text.count else { return " " }
        return text[text.index(text.startIndex, offsetBy: donePosition)]
    }
    
    func isCurrentChar(_ character: Character) -> Bool {
        if type == .space {
            return !isCompleted && character == " "
        }
        return currentChar == character
    }
    
    func shiftText() {
        if type == .space {
            isCompleted = true
            return
        }
        
        donePosition += 1
        isCompleted = donePosition >= text.count
        
        if isCompleted {
            doneText = text
            notDoneText = ""
        } else {
            doneText = String(text.prefix(donePosition))
            notDoneText = String(text.suffix(text.count - donePosition))
        }
    }
    
    func reset() {
        donePosition = 0
        isCompleted = false
        doneText = ""
        notDoneText = text
    }
}
