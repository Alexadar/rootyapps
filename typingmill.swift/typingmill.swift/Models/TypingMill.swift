//
//  TypingMill.swift
//  typingmill.swift
//
//  Created by Oleksandr Koreniuk on 20.09.2025.
//

import Foundation
import SwiftUI
import Combine

class TypingMill: ObservableObject {
    @Published var millElements: [MillElement] = []
    @Published var currentDifficulty: Int = 1
    @Published var isAnimating: Bool = false
    @Published var scrollOffset: CGFloat = 0
    
    private var textGenerator = TextGenerator()
    private var currentElementIndex: Int = 0
    private let speedMultiplier: CGFloat = 24
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        changeDifficulty(1)
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
        currentElementIndex = 0
        scrollOffset = 0
        
        // Generate initial text elements
        for _ in 0..<10 { // Generate enough elements to fill screen
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
            currentElement.shiftText()
            
            if currentElement.isCompleted {
                // Move to next element
                currentElement.isCurrent = false
                currentElementIndex += 1
                
                // Generate more elements if needed
                if currentElementIndex >= millElements.count - 5 {
                    generateNextElement()
                }
                
                // Set next element as current
                if currentElementIndex < millElements.count {
                    millElements[currentElementIndex].isCurrent = true
                }
                
                // Remove old elements to prevent memory issues
                if millElements.count > 20 {
                    millElements.removeFirst(2) // Remove word + space pair
                    currentElementIndex -= 2
                }
            }
        }
    }
    
    func updateScrolling() {
        guard currentElementIndex < millElements.count else { return }
        
        let currentElement = millElements[currentElementIndex]
        // Calculate scroll offset based on current element position
        // This is a simplified version - in a real implementation you'd calculate
        // based on actual text width and positioning
        let targetOffset = CGFloat(currentElementIndex) * 50 // Approximate width per element
        
        withAnimation(.linear(duration: 0.1)) {
            scrollOffset = targetOffset
        }
    }
}
