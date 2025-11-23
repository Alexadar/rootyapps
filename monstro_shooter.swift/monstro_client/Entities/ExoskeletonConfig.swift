import Foundation
import SpriteKit
import Yams

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

    private var exoskeletons: [Int: ExoskeletonConfig] = [:]

    private init() {
        loadConfigs()
    }

    private func loadConfigs() {
        guard let resourcePath = Bundle.main.resourcePath else {
            fatalError("[ExoskeletonManager] Bundle resource path not found")
        }

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) else {
            fatalError("[ExoskeletonManager] Failed to list bundle resources")
        }

        // Load all exoskeleton YAML files
        for filename in files where filename.hasSuffix(".yaml") {
            guard let path = Bundle.main.path(forResource: String(filename.dropLast(5)), ofType: "yaml"),
                  let yamlString = try? String(contentsOfFile: path, encoding: .utf8) else {
                continue
            }

            // Try to decode as ExoskeletonConfig - skip if not an exoskeleton config
            guard let config = try? YAMLDecoder().decode(ExoskeletonConfig.self, from: yamlString),
                  config.orderId > 0 else {
                continue
            }

            exoskeletons[config.id] = config
            print("[ExoskeletonManager] Loaded exoskeleton: \(config.name) (ID: \(config.id))")
        }

        guard !exoskeletons.isEmpty else {
            fatalError("[ExoskeletonManager] No exoskeleton configs loaded")
        }
    }

    func getExoskeleton(id: Int) -> ExoskeletonConfig? {
        return exoskeletons[id]
    }

    func getAllExoskeletons() -> [ExoskeletonConfig] {
        return exoskeletons.values.sorted { $0.orderId < $1.orderId }
    }
}
