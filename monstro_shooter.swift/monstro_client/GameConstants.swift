import Foundation
import CoreGraphics

/// Global game constants and configuration values
struct GameConstants {

    // MARK: - Player
    static let playerSpeed: CGFloat = 300.0
    static let playerSize: CGSize = CGSize(width: 60, height: 60)

    // MARK: - Monster
    static let monsterSpeed: CGFloat = 100.0
    static let monsterBoxSize: CGSize = CGSize(width: 28, height: 28)
    static let monsterRotationOffset: CGFloat = .pi / 4

    // MARK: - Bullet
    static let bulletSpeed: CGFloat = 800.0

    // MARK: - Spawn
    /// Spawn box size around player (monsters spawn from edges of this box)
    static let defaultSpawnBoxSize = CGSize(width: 4500, height: 4500)
    /// Monster spawn interval in seconds
    static let defaultMonsterSpawnInterval: TimeInterval = 2.0

    // MARK: - Camera
    /// Camera follow speed (0.0 = instant, 1.0 = very slow)
    static let cameraFollowSmoothing: CGFloat = 0.1

    // MARK: - HUD
    static let hudHorizontalMargin: CGFloat = 20
    static let hudTopMargin: CGFloat = 60
    static let hudRowSpacing: CGFloat = 40
    static let hudElementHeight: CGFloat = 32
    static let hudZPosition: CGFloat = 1000
    static let hudParallaxStrength: CGFloat = 1.0
    static let hudMaxParallaxOffset: CGFloat = 50.0
    static let hudParallaxLerpSpeed: CGFloat = 0.15
    static let hudParallaxReturnSpeed: CGFloat = 0.05

    // MARK: - Debug
    static let debugRotationStep: CGFloat = .pi / 8
}
