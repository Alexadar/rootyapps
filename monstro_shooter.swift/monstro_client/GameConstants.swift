import Foundation
import CoreGraphics

/// Global game constants and configuration values
struct GameConstants {

    // MARK: - Spawn Configuration
    /// Default spawn box size around player (monsters spawn from edges of this box)
    /// Set to 4500x4500 to cover all device resolutions
    static let defaultSpawnBoxSize = CGSize(width: 4500, height: 4500)

    /// Default monster spawn interval in seconds
    static let defaultMonsterSpawnInterval: TimeInterval = 2.0

    // MARK: - Camera Configuration
    /// Camera follow speed (0.0 = instant, 1.0 = very slow)
    /// Lower values = smoother/slower follow, Higher values = snappier follow
    static let cameraFollowSmoothing: CGFloat = 0.1

    // MARK: - Player Configuration
    static let playerSpeed: CGFloat = 300.0
    static let playerSize: CGSize = CGSize(width: 60, height: 60)

    // MARK: - Bullet Configuration
    static let bulletSpeed: CGFloat = 800.0

    // MARK: - Monster Configuration
    static let monsterSpeed: CGFloat = 100.0
    static let monsterBoxSize: CGSize = CGSize(width: 28, height: 28)
    static let monsterRotationOffset: CGFloat = .pi / 4

    // MARK: - Debug Configuration
    static let debugRotationStep: CGFloat = .pi / 8

    // MARK: - HUD Configuration
    /// Horizontal margin from screen edges
    static let hudHorizontalMargin: CGFloat = 20

    /// Vertical margin from top of screen
    static let hudTopMargin: CGFloat = 60

    /// Vertical spacing between HUD rows
    static let hudRowSpacing: CGFloat = 40

    /// HUD element heights
    static let hudElementHeight: CGFloat = 32

    /// HUD z-position (above all game elements)
    static let hudZPosition: CGFloat = 1000
}
