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
        let configDir = "configs/monsters"

        guard let resourcePath = Bundle.main.resourcePath else {
            fatalError("[MonsterRegistry] Bundle resource path not found")
        }

        let fullPath = resourcePath + "/" + configDir

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: fullPath) else {
            fatalError("[MonsterRegistry] Failed to list monster configs at \(fullPath)")
        }

        for filename in files where filename.hasSuffix(".yaml") {
            guard let path = Bundle.main.path(forResource: "\(configDir)/\(filename.dropLast(5))", ofType: "yaml") else {
                fatalError("[MonsterRegistry] Config file not found: \(filename)")
            }

            guard let yamlString = try? String(contentsOfFile: path, encoding: .utf8) else {
                fatalError("[MonsterRegistry] Failed to read config: \(filename)")
            }

            guard let config = try? YAMLDecoder().decode(MonsterConfig.self, from: yamlString) else {
                fatalError("[MonsterRegistry] Failed to decode config: \(filename)")
            }

            configs[config.monsterTypeID] = config
            print("Loaded monster config ID \(config.monsterTypeID) from \(filename)")
        }

        guard !configs.isEmpty else {
            fatalError("[MonsterRegistry] No monster configs loaded")
        }
    }

    func getConfig(forID id: Int) -> MonsterConfig? {
        return configs[id]
    }
}
