//
//  TypingMill.swift
//  typingmill.swift
//
//  Created by Oleksandr Koreniuk on 20.09.2025.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class TypingMill: ObservableObject {
    @Published var millElements: [MillElement] = []
    @Published var currentDifficulty: Int = 1
    @Published var isAnimating: Bool = false
    @Published var currentElementIndex: Int = 0
    @Published var currentCharacter: Character? = nil
    @Published var typingSpeed: Double = 0 // characters per minute
    @Published var correctKeystroke: Bool = false // Signal for correct keystrokes
    
    private var textGenerator = TextGenerator()
    private var cancellables = Set<AnyCancellable>()
    private var typingStartTime: Date?
    private var totalCharactersTyped: Int = 0
    private var lastSpeedUpdate: Date = Date()
    
    init() {
        changeDifficulty(1)
        // Ensure current character is set after initialization
        updateCurrentCharacter()
    }
    
    func changeDifficulty(_ difficulty: Int) {
        currentDifficulty = difficulty
        textGenerator.setDifficulty(difficulty)
        
        // Fade out animation
        withAnimation(.easeInOut(duration: 0.3)) {
            isAnimating = true
            for element in millElements {
                element.isFadedOut = true
            }
        }
        
        // Reset after fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.initiateText()
        }
    }
    
    private func initiateText() {
        millElements.removeAll()
        currentElementIndex = -1  // Temporary invalid value to force onChange trigger

        // Generate initial text elements
        for _ in 0..<30 { // Generate many more elements to ensure text extends far to the right
            generateNextElement()
        }

        // Set first element as current
        if !millElements.isEmpty {
            millElements[0].isCurrent = true
        }

        // Fade in animation
        withAnimation(.easeInOut(duration: 0.3)) {
            isAnimating = false
            for element in millElements {
                element.isFadedOut = false
            }
        }

        // Set index to 0 AFTER elements exist - this triggers onChange in the view
        currentElementIndex = 0
        updateCurrentCharacter()
    }
    
    private func generateNextElement() {
        // Add word element
        let word = textGenerator.getNextWord()
        let wordElement = MillElement(type: .word, text: word)
        millElements.append(wordElement)
        
        // Add space element
        let spaceElement = MillElement(type: .space)
        millElements.append(spaceElement)
    }
    
    func processKeyPress(_ character: Character) {
        guard !isAnimating,
              currentElementIndex < millElements.count else { return }
        
        let currentElement = millElements[currentElementIndex]
        
        if currentElement.isCurrentChar(character) {
            // Signal correct keystroke for animations
            correctKeystroke = true
            
            // Track typing speed
            updateTypingSpeed()
            
            currentElement.shiftText()
            
            if currentElement.isCompleted {
                // Move to next element
                currentElement.isCurrent = false
                currentElementIndex += 1
                
                // Generate more elements if needed - wait until much closer to the end
                if currentElementIndex >= millElements.count - 15 {
                    generateNextElement()
                }
                
                // Set next element as current with bounds checking
                if currentElementIndex >= 0 && currentElementIndex < millElements.count {
                    millElements[currentElementIndex].isCurrent = true
                }
                
                // Remove old elements to prevent memory issues, but only after we have enough elements
                // and only if we're far enough into the typing to maintain continuity
                if millElements.count > 50 && currentElementIndex > 20 {
                    millElements.removeFirst(2) // Remove word + space pair
                    currentElementIndex = max(0, currentElementIndex - 2)
                }
            }
            
            // Update current character after any changes
            updateCurrentCharacter()
            
            // Reset the signal after a brief moment using a task
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                await MainActor.run {
                    self.correctKeystroke = false
                }
            }
        }
    }
    
    private func updateTypingSpeed() {
        let now = Date()
        
        // Initialize typing start time on first keypress
        if typingStartTime == nil {
            typingStartTime = now
            lastSpeedUpdate = now
        }
        
        totalCharactersTyped += 1
        
        // Update speed every second or so
        if now.timeIntervalSince(lastSpeedUpdate) >= 1.0 {
            if let startTime = typingStartTime {
                let totalTime = now.timeIntervalSince(startTime)
                if totalTime > 0 {
                    typingSpeed = Double(totalCharactersTyped) / totalTime * 60 // characters per minute
                }
            }
            lastSpeedUpdate = now
        }
    }
    
    func getCurrentCharacter() -> Character? {
        guard !isAnimating,
              currentElementIndex < millElements.count else { return nil }
        
        let currentElement = millElements[currentElementIndex]
        return currentElement.currentChar
    }
    
    private func updateCurrentCharacter() {
        currentCharacter = getCurrentCharacter()
    }
    
}
