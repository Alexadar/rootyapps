import Foundation
import SpriteKit

// MARK: - Exoskeleton Configuration
struct ExoskeletonConfig: Codable, Identifiable {
    let id: Int
    let name: String

    // Defense & Speed
    let defence: Double          // Damage reduction (absolute value subtracted from incoming damage)
    let speed: Double            // Movement speed multiplier (1.0 = normal, >1.0 = faster, <1.0 = slower)

    // Visual Resources
    let gameResourceSprite: String?
    let lobbyResourceSprite: String?

    // Requirements & Pricing
    let levelRequirement: Int
    let rankRequirement: Int
    let buyPriceSoft: Int
    let buyPriceHard: Int
    let sellPriceSoft: Int
    let sellPriceHard: Int
    let marketAvailability: Bool
    let orderId: Int

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

    // MARK: - Default Exoskeletons

    static let standardSuit = ExoskeletonConfig(
        id: 1,
        name: "Standard Suit",
        defence: 0.0,
        speed: 1.0,
        gameResourceSprite: "exoskeleton_standard",
        lobbyResourceSprite: "exoskeleton_standard_preview",
        levelRequirement: 0,
        rankRequirement: 0,
        buyPriceSoft: 0,
        buyPriceHard: 0,
        sellPriceSoft: 0,
        sellPriceHard: 0,
        marketAvailability: true,
        orderId: 1,
        nameLocalizations: Localizations(enUs: "Standard Suit", ruRu: "Стандартный костюм")
    )

    static let lightArmor = ExoskeletonConfig(
        id: 2,
        name: "Light Armor",
        defence: 1.0,         // Reduces damage by 1 point
        speed: 1.05,          // 5% faster
        gameResourceSprite: "exoskeleton_light",
        lobbyResourceSprite: "exoskeleton_light_preview",
        levelRequirement: 3,
        rankRequirement: 0,
        buyPriceSoft: 3000,
        buyPriceHard: 75,
        sellPriceSoft: 1500,
        sellPriceHard: 37,
        marketAvailability: true,
        orderId: 2,
        nameLocalizations: Localizations(enUs: "Light Armor", ruRu: "Лёгкая броня")
    )

    static let mediumArmor = ExoskeletonConfig(
        id: 3,
        name: "Medium Armor",
        defence: 2.0,         // Reduces damage by 2 points
        speed: 1.0,           // Normal speed
        gameResourceSprite: "exoskeleton_medium",
        lobbyResourceSprite: "exoskeleton_medium_preview",
        levelRequirement: 7,
        rankRequirement: 0,
        buyPriceSoft: 8000,
        buyPriceHard: 150,
        sellPriceSoft: 4000,
        sellPriceHard: 75,
        marketAvailability: true,
        orderId: 3,
        nameLocalizations: Localizations(enUs: "Medium Armor", ruRu: "Средняя броня")
    )

    static let heavyArmor = ExoskeletonConfig(
        id: 4,
        name: "Heavy Armor",
        defence: 3.5,         // Reduces damage by 3.5 points
        speed: 0.85,          // 15% slower
        gameResourceSprite: "exoskeleton_heavy",
        lobbyResourceSprite: "exoskeleton_heavy_preview",
        levelRequirement: 12,
        rankRequirement: 0,
        buyPriceSoft: 18000,
        buyPriceHard: 350,
        sellPriceSoft: 9000,
        sellPriceHard: 175,
        marketAvailability: true,
        orderId: 4,
        nameLocalizations: Localizations(enUs: "Heavy Armor", ruRu: "Тяжёлая броня")
    )

    /// Get localized name (defaults to ru-ru then en-us)
    func getLocalizedName() -> String {
        return nameLocalizations?.ruRu
            ?? nameLocalizations?.enUs
            ?? name
    }
}

// MARK: - Exoskeleton Manager
class ExoskeletonManager {
    static let shared = ExoskeletonManager()

    private var availableExoskeletons: [Int: ExoskeletonConfig] = [
        1: .standardSuit,
        2: .lightArmor,
        3: .mediumArmor,
        4: .heavyArmor
    ]

    private init() {}

    func getExoskeleton(id: Int) -> ExoskeletonConfig? {
        return availableExoskeletons[id]
    }

    func getAllExoskeletons() -> [ExoskeletonConfig] {
        return availableExoskeletons.values.sorted { $0.orderId < $1.orderId }
    }
}
