import Foundation
import CoreGraphics

/// Monster configuration loaded from YAML
struct MonsterConfig: Codable {
    let monsterTypeID: Int
    let speed: CGFloat
    let boxWidth: CGFloat
    let boxHeight: CGFloat
    let damage: CGFloat
    let health: CGFloat
    let hitCooldown: Double
    let rotationOffset: CGFloat
    let useDirectSteering: Bool
    let walkAnimationDirectory: String
    let dyingAnimationDirectory: String
    let walkFrameRate: Double
    let dyingFrameRate: Double
    let deathSounds: [String]

    var boxSize: CGSize {
        CGSize(width: boxWidth, height: boxHeight)
    }

    var name: String {
        GameConstants.MonsterType(rawValue: monsterTypeID)?.name ?? "Unknown"
    }
}
