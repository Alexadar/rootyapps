import Foundation
import Yams

/// Singleton that loads and manages monster configurations
class MonsterRegistry {
    static let shared = MonsterRegistry()

    private var configs: [Int: MonsterConfig] = [:]

    private init() {
        loadConfigs()
    }

    private func loadConfigs() {
        guard let resourcePath = Bundle.main.resourcePath else {
            fatalError("[MonsterRegistry] Bundle resource path not found")
        }

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) else {
            fatalError("[MonsterRegistry] Failed to list bundle resources at \(resourcePath)")
        }

        for filename in files where filename.hasSuffix(".yaml") {
            guard let path = Bundle.main.path(forResource: String(filename.dropLast(5)), ofType: "yaml"),
                  let yamlString = try? String(contentsOfFile: path, encoding: .utf8) else {
                continue
            }

            // Try to decode as MonsterConfig - skip if it's not a monster config
            guard let config = try? YAMLDecoder().decode(MonsterConfig.self, from: yamlString),
                  config.monsterTypeID > 0 else {
                continue
            }

            configs[config.monsterTypeID] = config
            print("[MonsterRegistry] Loaded monster: ID \(config.monsterTypeID) from \(filename)")
        }

        guard !configs.isEmpty else {
            fatalError("[MonsterRegistry] No monster configs loaded")
        }
    }

    func getConfig(forID id: Int) -> MonsterConfig? {
        return configs[id]
    }
}
