import Foundation
import CoreGraphics

struct GameConstants {
    // Player
    static let playerEmoji = "🐷"
    
    // Treasures
    static let treasureEmojis = ["💎", "💰", "🏆", "🌟", "🍎", "🥕", "🌽", "🍇"]
    
    // Enemies
    static let enemyEmojis = ["👻", "🦇", "🕷️", "🐍", "🔥", "💀", "👹", "🐺"]
    
    // Grid sizes based on screen size
    static func gridSize(for screenSize: CGSize) -> (width: Int, height: Int) {
        let baseWidth = 15
        let baseHeight = 12
        
        // Adjust grid size based on screen dimensions
        let aspectRatio = screenSize.width / screenSize.height
        
        if aspectRatio > 1.5 {
            // Wide screen
            return (width: baseWidth + 5, height: baseHeight)
        } else if aspectRatio < 0.8 {
            // Tall screen
            return (width: baseWidth, height: baseHeight + 3)
        }
        
        return (width: baseWidth, height: baseHeight)
    }
    
    // Level-based configurations
    static func treasureCount(for level: Int) -> Int {
        return min(3 + level, 8)
    }
    
    static func enemyCount(for level: Int) -> Int {
        return min(1 + (level - 1) / 2, 5)
    }
    
    static func treasureValue(for emoji: String) -> Int {
        switch emoji {
        case "💎":
            return 50
        case "💰":
            return 30
        case "🏆":
            return 100
        case "🌟":
            return 25
        case "🍎", "🥕", "🌽", "🍇":
            return 10
        default:
            return 20
        }
    }
    
    static func enemySpeed(for difficulty: Difficulty) -> Double {
        switch difficulty {
        case .easy:
            return 0.5
        case .medium:
            return 1.0
        case .hard:
            return 1.5
        }
    }
    
    // Maze generation parameters
    static let wallDensity: Double = 0.3
    static let minPathWidth: Int = 2
    
    // Animation durations
    static let playerMoveSpeed: Double = 0.15
    static let enemyMoveSpeed: Double = 0.2
    static let treasureAnimationSpeed: Double = 0.5
    
    // Scoring
    static let levelCompletionBonus: Int = 100
    static let lifeValue: Int = 500
}
