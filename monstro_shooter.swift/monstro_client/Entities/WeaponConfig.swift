import Foundation
import SpriteKit

// MARK: - Weapon Types
enum WeaponType: Int, Codable {
    case pistol = 1      // Single shot, balanced
    case dualPistols = 2 // Two bullets, fast
    case rifle = 3       // Fast fire rate, medium damage
    case minigun = 4     // Very fast, lower damage, spray
    case shotgun = 5     // Close range, multiple pellets
    case sniperRifle = 6 // High damage, slow fire rate
}

// MARK: - Weapon Configuration
struct WeaponConfig: Codable, Identifiable {
    let id: Int
    let name: String
    let type: WeaponType

    // Localization (optional)
    struct Localizations: Codable {
        let enUs: String?
        let ruRu: String?

        enum CodingKeys: String, CodingKey {
            case enUs = "en-us"
            case ruRu = "ru-ru"
        }
    }

    let nameLocalizations: Localizations?

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
        nameLocalizations: Localizations(enUs: "Pistol", ruRu: "Пистолет"),
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
        nameLocalizations: Localizations(enUs: "Rifle", ruRu: "Винтовка"),
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
        nameLocalizations: Localizations(enUs: "Minigun", ruRu: "Миниган"),
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

    static let dualPistols = WeaponConfig(
        id: 2,
        name: "Dual Pistols",
        type: .dualPistols,
        nameLocalizations: Localizations(enUs: "Dual Pistols", ruRu: "Два пистолета"),
        damage: 8,
        shotRange: 750,
        shotDelay: 0.4,
        magazineSize: 24,
        reloadTime: 2.5,
        bulletsPerShot: 2,
        bulletSpeed: 750,
        bulletDeviation: 0.052,  // ~3 degrees
        maxDeviation: 0.052,
        penetrationPower: 1,
        bulletStartScale: 0.3,
        bulletMaxScale: 1.0,
        bulletScaleGrowth: 0.05,
        bulletTextureName: "bullet_pistol",
        weaponSoundName: "weapon_pistol"
    )

    static let shotgun = WeaponConfig(
        id: 5,
        name: "Shotgun",
        type: .shotgun,
        nameLocalizations: Localizations(enUs: "Shotgun", ruRu: "Дробовик"),
        damage: 7,
        shotRange: 400,
        shotDelay: 0.8,
        magazineSize: 8,
        reloadTime: 3.5,
        bulletsPerShot: 7,
        bulletSpeed: 700,
        bulletDeviation: 0.140,  // ~8 degrees
        maxDeviation: 0.262,     // ~15 degrees
        penetrationPower: 1,
        bulletStartScale: 0.25,
        bulletMaxScale: 0.7,
        bulletScaleGrowth: 0.04,
        bulletTextureName: "bullet_shotgun",
        weaponSoundName: "weapon_shotgun"
    )

    static let sniperRifle = WeaponConfig(
        id: 6,
        name: "Sniper Rifle",
        type: .sniperRifle,
        nameLocalizations: Localizations(enUs: "Sniper Rifle", ruRu: "Снайперская винтовка"),
        damage: 50,
        shotRange: 1500,
        shotDelay: 1.2,
        magazineSize: 5,
        reloadTime: 4.0,
        bulletsPerShot: 1,
        bulletSpeed: 1500,
        bulletDeviation: 0.009,  // ~0.5 degrees
        maxDeviation: 0.009,
        penetrationPower: 5,
        bulletStartScale: 0.4,
        bulletMaxScale: 1.2,
        bulletScaleGrowth: 0.06,
        bulletTextureName: "bullet_sniper",
        weaponSoundName: "weapon_sniper"
    )

    /// Get localized name (defaults to ru-ru then en-us)
    func getLocalizedName() -> String {
        return nameLocalizations?.ruRu
            ?? nameLocalizations?.enUs
            ?? name
    }
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
        2: .dualPistols,
        3: .rifle,
        4: .minigun,
        5: .shotgun,
        6: .sniperRifle
    ]

    private init() {}

    func getWeapon(id: Int) -> WeaponConfig? {
        return availableWeapons[id]
    }

    func getWeapon(type: WeaponType) -> WeaponConfig? {
        return availableWeapons.values.first { $0.type == type }
    }

    func getAllWeapons() -> [WeaponConfig] {
        return availableWeapons.values.sorted { $0.id < $1.id }
    }
}
