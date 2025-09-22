import SwiftUI
import Combine

enum GameState {
    case menu
    case playing
    case paused
    case gameOver
}

enum Difficulty: String, CaseIterable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
}

enum ControlType: String, CaseIterable {
    case swipe = "Swipe"
    case dpad = "D-Pad"
    #if os(macOS)
    case keyboard = "Keyboard"
    #endif
}

class GameEngine: ObservableObject {
    @Published var gameState: GameState = .menu
    @Published var score: Int = 0
    @Published var lives: Int = 3
    @Published var currentLevel: Int = 1
    @Published var difficulty: Difficulty = .medium
    @Published var soundEnabled: Bool = true
    @Published var hapticEnabled: Bool = true
    @Published var controlType: ControlType = .swipe
    
    var player: Player = Player()
    var enemies: [Enemy] = []
    var treasures: [Treasure] = []
    var maze: [[MazeCell]] = []
    var exitPosition: GridPosition = GridPosition(x: 0, y: 0)
    
    func startGame() {
        gameState = .playing
        score = 0
        lives = 3
        currentLevel = 1
        player = Player()
        enemies = []
        treasures = []
    }
    
    func restartGame() {
        startGame()
    }
    
    func returnToMenu() {
        gameState = .menu
    }
    
    func togglePause() {
        switch gameState {
        case .playing:
            gameState = .paused
        case .paused:
            gameState = .playing
        default:
            break
        }
    }
    
    func collectTreasure(at index: Int) {
        guard index < treasures.count else { return }
        treasures[index].collected = true
        score += treasures[index].value
        
        if soundEnabled {
            // Play collection sound
        }
        
        #if os(iOS)
        if hapticEnabled {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
        #endif
    }
    
    func playerHit() {
        lives -= 1
        
        if soundEnabled {
            // Play hit sound
        }
        
        #if os(iOS)
        if hapticEnabled {
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
        }
        #endif
    }
    
    func gameOver() {
        gameState = .gameOver
    }
    
    func nextLevel() {
        currentLevel += 1
        score += 100 * currentLevel // Bonus for completing level
        
        if soundEnabled {
            // Play level complete sound
        }
        
        #if os(iOS)
        if hapticEnabled {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        }
        #endif
    }
}
