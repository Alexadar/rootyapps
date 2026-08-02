import Foundation
import SpriteKit
import Yams

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

    private var weapons: [Int: WeaponConfig] = [:]

    private init() {
        loadConfigs()
    }

    private func loadConfigs() {
        guard let resourcePath = Bundle.main.resourcePath else {
            fatalError("[WeaponManager] Bundle resource path not found")
        }

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) else {
            fatalError("[WeaponManager] Failed to list bundle resources")
        }

        // Load all weapon YAML files
        for filename in files where filename.hasSuffix(".yaml") {
            guard let path = Bundle.main.path(forResource: String(filename.dropLast(5)), ofType: "yaml"),
                  let yamlString = try? String(contentsOfFile: path, encoding: .utf8) else {
                continue
            }

            // Try to decode as WeaponConfig - skip if not a weapon config
            guard let config = try? YAMLDecoder().decode(WeaponConfig.self, from: yamlString),
                  !config.weaponSoundName.isEmpty else {
                continue
            }

            weapons[config.id] = config
            print("[WeaponManager] Loaded weapon: \(config.name) (ID: \(config.id))")
        }

        guard !weapons.isEmpty else {
            fatalError("[WeaponManager] No weapon configs loaded")
        }
    }

    func getWeapon(id: Int) -> WeaponConfig? {
        return weapons[id]
    }

    func getWeapon(type: WeaponType) -> WeaponConfig? {
        return weapons.values.first { $0.type == type }
    }

    func getAllWeapons() -> [WeaponConfig] {
        return weapons.values.sorted { $0.id < $1.id }
    }
}
