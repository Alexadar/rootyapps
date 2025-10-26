import Foundation
import SpriteKit

// MARK: - Weapon Types
enum WeaponType: Int, Codable {
    case pistol = 1      // Single shot, balanced
    case dualPistols = 2 // Two bullets, fast
    case rifle = 3       // Fast fire rate, medium damage
    case minigun = 4     // Very fast, lower damage, spray
}

// MARK: - Weapon Configuration
struct WeaponConfig: Codable {
    let id: Int
    let name: String
    let type: WeaponType

    // Damage & Range
    let damage: Double
    let shotRange: CGFloat

    // Fire Rate & Magazine
    let shotDelay: TimeInterval      // Time between shots
    let magazineSize: Int            // Bullets per magazine
    let reloadTime: TimeInterval     // Reload duration

    // Bullet Behavior
    let bulletsPerShot: Int          // 1 for normal, 5+ for shotgun
    let bulletSpeed: CGFloat
    let bulletDeviation: CGFloat     // Spread angle in radians
    let maxDeviation: CGFloat
    let penetrationPower: Int        // How many enemies to pierce

    // Visual
    let bulletStartScale: CGFloat    // 0.3
    let bulletMaxScale: CGFloat      // 1.0
    let bulletScaleGrowth: CGFloat   // 0.05 per frame
    let bulletTextureName: String

    // Audio
    let weaponSoundName: String      // "weapon_pistol", "weapon_rifle", etc.

    // MARK: - Default Weapons

    static let pistol = WeaponConfig(
        id: 1,
        name: "Pistol",
        type: .pistol,
        damage: 10,
        shotRange: 800,
        shotDelay: 0.5,
        magazineSize: 12,
        reloadTime: 2.0,
        bulletsPerShot: 1,
        bulletSpeed: 800,
        bulletDeviation: 0.035,  // ~2 degrees
        maxDeviation: 0.035,
        penetrationPower: 1,
        bulletStartScale: 0.3,
        bulletMaxScale: 1.0,
        bulletScaleGrowth: 0.05,
        bulletTextureName: "bullet_pistol",
        weaponSoundName: "weapon_pistol"
    )

    static let rifle = WeaponConfig(
        id: 3,
        name: "Rifle",
        type: .rifle,
        damage: 15,
        shotRange: 1000,
        shotDelay: 0.15,
        magazineSize: 30,
        reloadTime: 3.0,
        bulletsPerShot: 1,
        bulletSpeed: 1000,
        bulletDeviation: 0.017,  // ~1 degree
        maxDeviation: 0.017,
        penetrationPower: 2,
        bulletStartScale: 0.3,
        bulletMaxScale: 1.0,
        bulletScaleGrowth: 0.05,
        bulletTextureName: "bullet_rifle",
        weaponSoundName: "weapon_rifle"
    )

    static let minigun = WeaponConfig(
        id: 4,
        name: "Minigun",
        type: .minigun,
        damage: 5,
        shotRange: 600,
        shotDelay: 0.08,
        magazineSize: 200,
        reloadTime: 5.0,
        bulletsPerShot: 1,
        bulletSpeed: 900,
        bulletDeviation: 0.087,  // ~5 degrees (spray)
        maxDeviation: 0.174,     // ~10 degrees
        penetrationPower: 1,
        bulletStartScale: 0.2,
        bulletMaxScale: 0.8,
        bulletScaleGrowth: 0.04,
        bulletTextureName: "bullet_minigun",
        weaponSoundName: "weapon_minigun"
    )
}

// MARK: - Bullet Info
struct BulletInfo {
    let damage: Double
    let speed: CGFloat
    let range: CGFloat
    let deviation: CGFloat
    let penetration: Int
    let startScale: CGFloat
    let maxScale: CGFloat
    let scaleGrowth: CGFloat
    let textureName: String
}

// MARK: - Weapon Manager
class WeaponManager {
    static let shared = WeaponManager()

    private var availableWeapons: [Int: WeaponConfig] = [
        1: .pistol,
        3: .rifle,
        4: .minigun
    ]

    private init() {}

    func getWeapon(id: Int) -> WeaponConfig? {
        return availableWeapons[id]
    }

    func getWeapon(type: WeaponType) -> WeaponConfig? {
        return availableWeapons.values.first { $0.type == type }
    }
}
