import Foundation
import CoreGraphics
#if !os(macOS)
import UIKit
#endif

/// Global game constants and configuration values
struct GameConstants {

    // MARK: - Player
    static let playerSpeed: CGFloat = 300.0
    static let playerSize: CGSize = CGSize(width: 60, height: 60)

    // MARK: - Monster
    static let monsterSpeed: CGFloat = 100.0
    static let monsterBoxSize: CGSize = CGSize(width: 28, height: 28)
    static let monsterRotationOffset: CGFloat = .pi / 4

    /// Monster type IDs matching database/JSON configuration
    enum MonsterType: Int {
        case bug = 1
        case berserker = 2
        case bird = 3
        case bug2 = 4
        case bird2 = 5
        case bug3 = 6
        case berserker2 = 7
        case bird3 = 8
        case walker3 = 9
        case bug4 = 10
        case bird4 = 11
        case walker4 = 12
        case bug5 = 13
        case bird5 = 14
        case walker = 15
        case berserker4 = 16
        case bug6 = 17
        case walker6 = 18
        case walker2 = 22
        case berserker6 = 23
        case bird6 = 24

        var name: String {
            switch self {
            case .bug: return "Bug"
            case .berserker: return "Berserker"
            case .bird: return "Bird"
            case .bug2: return "Bug2"
            case .bird2: return "Bird2"
            case .bug3: return "Bug3"
            case .berserker2: return "Berserker2"
            case .bird3: return "Bird3"
            case .walker3: return "Walker3"
            case .bug4: return "Bug4"
            case .bird4: return "Bird4"
            case .walker4: return "Walker4"
            case .bug5: return "Bug5"
            case .bird5: return "Bird5"
            case .walker: return "Walker"
            case .berserker4: return "Berserker4"
            case .bug6: return "Bug6"
            case .walker6: return "Walker6"
            case .walker2: return "Walker2"
            case .berserker6: return "Berserker6"
            case .bird6: return "Bird6"
            }
        }
    }

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
    /// Camera zoom scale (0.5 = 2x zoom in, 1.0 = normal, 2.0 = 2x zoom out)
    /// Platform-specific for optimal viewing experience
    static var cameraScale: CGFloat {
        #if os(macOS)
        return 0.7
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 0.7  // iPadOS
        } else {
            return 1.0  // iOS (iPhone)
        }
        #endif
    }

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

    // MARK: - Tutorial
    static let tutorialMoveHintDelay: TimeInterval = 5.0      // Show move hint after 5 sec no movement
    static let tutorialShootHintDelay: TimeInterval = 30.0    // Show shoot hint after 30 sec no shooting
    static let tutorialKillHintDelay: TimeInterval = 60.0     // Show kill hint after 1 min no kills
    static let tutorialHintDisplayDuration: TimeInterval = 1.0 // Hint visible for 1 sec
    static let tutorialHintFadeDuration: TimeInterval = 0.5   // Fade in/out duration
    static let tutorialHintPauseDuration: TimeInterval = 2.0  // Pause between hints

    // MARK: - Touch Controls (iOS/iPadOS)
    /// Physical size of touch control zones in centimeters
    static let touchControlSizeCm: CGFloat = 4.0
    /// Joystick active radius as percentage of control zone size
    static let touchJoystickRadiusRatio: CGFloat = 0.35
    /// Control indicator circle radius in points
    static let touchIndicatorRadius: CGFloat = 18.0
    /// Aim indicator circle radius in points
    static let touchAimIndicatorRadius: CGFloat = 16.0

    // MARK: - Debug
    static let debugRotationStep: CGFloat = .pi / 8

    /// Show debug touch controls (joystick regions, knobs, aim markers)
    /// Automatically disabled in release builds
    static var showDebugControls: Bool {
        #if DEBUG
        return false
        #else
        return false
        #endif
    }

    /// Show debug line at bottom of screen (for testing touch regions)
    /// Automatically disabled in release builds
    static var showDebugLine: Bool {
        #if DEBUG
        return false
        #else
        return false
        #endif
    }
}
