import SwiftUI
import Combine

enum Direction: CaseIterable {
    case up, down, left, right
    
    static func random() -> Direction {
        return Direction.allCases.randomElement() ?? .up
    }
}

class InputHandler: ObservableObject {
    weak var gameEngine: GameEngine?
    @Published var currentDirection: Direction?
    
    func handleDirection(_ direction: Direction) {
        currentDirection = direction
    }
    
    func handleSwipe(_ value: DragGesture.Value) {
        let horizontalAmount = value.translation.width
        let verticalAmount = value.translation.height
        
        if abs(horizontalAmount) > abs(verticalAmount) {
            // Horizontal swipe
            if horizontalAmount < 0 {
                handleDirection(.left)
            } else {
                handleDirection(.right)
            }
        } else {
            // Vertical swipe
            if verticalAmount < 0 {
                handleDirection(.up)
            } else {
                handleDirection(.down)
            }
        }
    }
    
    #if os(macOS)
    func handleKeyPress(_ key: String) {
        switch key.lowercased() {
        case "w", "arrowup":
            handleDirection(.up)
        case "s", "arrowdown":
            handleDirection(.down)
        case "a", "arrowleft":
            handleDirection(.left)
        case "d", "arrowright":
            handleDirection(.right)
        default:
            break
        }
    }
    #endif
}
