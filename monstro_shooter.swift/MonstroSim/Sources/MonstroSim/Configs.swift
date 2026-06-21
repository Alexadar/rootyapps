import Foundation

// Loads the SAME data files the shipping game uses:
//   - Monster / weapon / exoskeleton stats from Assets/configs/**/*.yaml
//   - Maps from Resources/MapConfigs/map_XXXX.json
// The unit YAMLs are flat `key: value`, so a tiny scalar parser avoids any YAML dependency.

// MARK: - Minimal flat-YAML scalar parser
enum MiniYAML {
    /// Parse top-level `key: value` scalar lines. Ignores indented lines, list items, comments.
    static func scalars(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            // Skip indented (nested) lines, list items, blanks, comments.
            if line.first == " " || line.first == "\t" { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("-") { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.isEmpty { continue }  // nested block (e.g. nameLocalizations:)
            if let hash = value.firstIndex(of: "#") {
                value = String(value[..<hash]).trimmingCharacters(in: .whitespaces)
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            out[key] = value
        }
        return out
    }
}

// MARK: - Unit configs
public struct MonsterCfg {
    public let typeID: Int
    public let speed: Double
    public let boxWidth: Double
    public let boxHeight: Double
    public let damage: Double
    public let health: Double
    public let hitCooldown: Double
    public let rotationOffset: Double
    public let useDirectSteering: Bool

    init?(_ d: [String: String]) {
        guard let id = d["monsterTypeID"].flatMap(Int.init),
              let speed = d["speed"].flatMap(Double.init),
              let bw = d["boxWidth"].flatMap(Double.init),
              let bh = d["boxHeight"].flatMap(Double.init),
              let dmg = d["damage"].flatMap(Double.init),
              let hp = d["health"].flatMap(Double.init) else { return nil }
        self.typeID = id
        self.speed = speed
        self.boxWidth = bw
        self.boxHeight = bh
        self.damage = dmg
        self.health = hp
        self.hitCooldown = d["hitCooldown"].flatMap(Double.init) ?? 1.0
        self.rotationOffset = d["rotationOffset"].flatMap(Double.init) ?? 0
        self.useDirectSteering = (d["useDirectSteering"] ?? "false") == "true"
    }
}

public struct WeaponCfg {
    public let id: Int
    public let damage: Double
    public let shotRange: Double
    public let shotDelay: Double
    public let magazineSize: Int
    public let reloadTime: Double
    public let bulletsPerShot: Int
    public let bulletSpeed: Double
    public let bulletDeviation: Double
    public let penetrationPower: Int

    init?(_ d: [String: String]) {
        guard let id = d["id"].flatMap(Int.init),
              let dmg = d["damage"].flatMap(Double.init),
              let range = d["shotRange"].flatMap(Double.init),
              let delay = d["shotDelay"].flatMap(Double.init),
              let mag = d["magazineSize"].flatMap(Int.init),
              let reload = d["reloadTime"].flatMap(Double.init) else { return nil }
        self.id = id
        self.damage = dmg
        self.shotRange = range
        self.shotDelay = delay
        self.magazineSize = mag
        self.reloadTime = reload
        self.bulletsPerShot = d["bulletsPerShot"].flatMap(Int.init) ?? 1
        self.bulletSpeed = d["bulletSpeed"].flatMap(Double.init) ?? 800
        self.bulletDeviation = d["bulletDeviation"].flatMap(Double.init) ?? 0
        self.penetrationPower = d["penetrationPower"].flatMap(Int.init) ?? 1
    }
}

public struct ExoCfg {
    public let id: Int
    public let defence: Double
    public let speed: Double

    init?(_ d: [String: String]) {
        guard let id = d["id"].flatMap(Int.init),
              let def = d["defence"].flatMap(Double.init),
              let spd = d["speed"].flatMap(Double.init) else { return nil }
        self.id = id; self.defence = def; self.speed = spd
    }
}

// MARK: - Map config (JSON, subset of MapConfig used by the sim)
public struct MapCfg: Codable {
    public var id: Int
    public var landingDuration: Int
    public var monsterSpawnWaves: [Wave]
    public var monsterTypes: [TypePeriod]
    public var defaultNameLocalizations: [String: String]?

    public struct Wave: Codable { public var startTime: Int; public var count: Int
        public init(startTime: Int, count: Int) { self.startTime = startTime; self.count = count } }
    public struct TypePeriod: Codable { public var startTime: Int; public var monsterTypeIds: [Int]
        public init(startTime: Int, monsterTypeIds: [Int]) { self.startTime = startTime; self.monsterTypeIds = monsterTypeIds } }

    public init(id: Int, landingDuration: Int, monsterSpawnWaves: [Wave], monsterTypes: [TypePeriod], defaultNameLocalizations: [String: String]? = nil) {
        self.id = id
        self.landingDuration = landingDuration
        self.monsterSpawnWaves = monsterSpawnWaves
        self.monsterTypes = monsterTypes
        self.defaultNameLocalizations = defaultNameLocalizations
    }

    public var name: String { defaultNameLocalizations?["ru-ru"] ?? defaultNameLocalizations?["en-us"] ?? "map \(id)" }
}

// MARK: - Compiled level (mirrors convertMapConfigToLevel)
public struct SimWave {
    public let startTime: Double
    public let count: Int
    public let typeIDs: [Int]
}

public struct SimLevel {
    public let id: Int
    public let name: String
    public let durationSeconds: Double
    public let waves: [SimWave]
    public var expectedTotal: Int { waves.reduce(0) { $0 + $1.count } }

    /// Mirrors GameScene.convertMapConfigToLevel: each spawn wave with count>0 spawns from ALL
    /// available monster types (flattened across monsterTypes periods).
    public init(_ map: MapCfg) {
        self.id = map.id
        self.name = map.name
        self.durationSeconds = Double(map.landingDuration)
        let allTypes = map.monsterTypes.flatMap { $0.monsterTypeIds }
        var w: [SimWave] = []
        for sw in map.monsterSpawnWaves where sw.count > 0 && !allTypes.isEmpty {
            w.append(SimWave(startTime: Double(sw.startTime), count: sw.count, typeIDs: allTypes))
        }
        self.waves = w
    }
}

// MARK: - Loaders
public enum ConfigLoader {
    public static func loadMonsters(dir: String) -> [Int: MonsterCfg] {
        var out: [Int: MonsterCfg] = [:]
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return out }
        for f in files where f.hasSuffix(".yaml") {
            guard let text = try? String(contentsOfFile: dir + "/" + f, encoding: .utf8),
                  let cfg = MonsterCfg(MiniYAML.scalars(text)) else { continue }
            out[cfg.typeID] = cfg
        }
        return out
    }

    public static func loadWeapons(dir: String) -> [Int: WeaponCfg] {
        var out: [Int: WeaponCfg] = [:]
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return out }
        for f in files where f.hasSuffix(".yaml") {
            guard let text = try? String(contentsOfFile: dir + "/" + f, encoding: .utf8),
                  let cfg = WeaponCfg(MiniYAML.scalars(text)) else { continue }
            out[cfg.id] = cfg
        }
        return out
    }

    public static func loadExoskeletons(dir: String) -> [Int: ExoCfg] {
        var out: [Int: ExoCfg] = [:]
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return out }
        for f in files where f.hasSuffix(".yaml") {
            guard let text = try? String(contentsOfFile: dir + "/" + f, encoding: .utf8),
                  let cfg = ExoCfg(MiniYAML.scalars(text)) else { continue }
            out[cfg.id] = cfg
        }
        return out
    }

    public static func loadMap(path: String) -> MapCfg? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(MapCfg.self, from: data)
    }

    public static func saveMap(_ map: MapCfg, path: String) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(map).write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - Game data bundle (all configs the sim needs)
public struct GameData {
    public let monsters: [Int: MonsterCfg]
    public let weapons: [Int: WeaponCfg]
    public let exoskeletons: [Int: ExoCfg]

    public init(monsters: [Int: MonsterCfg], weapons: [Int: WeaponCfg], exoskeletons: [Int: ExoCfg]) {
        self.monsters = monsters
        self.weapons = weapons
        self.exoskeletons = exoskeletons
    }

    /// Load from a `monstro_client` checkout. `root` points at the monstro_client/ dir.
    public static func load(clientRoot root: String) -> GameData {
        GameData(
            monsters: ConfigLoader.loadMonsters(dir: root + "/Assets/configs/monsters"),
            weapons: ConfigLoader.loadWeapons(dir: root + "/Assets/configs/weapons"),
            exoskeletons: ConfigLoader.loadExoskeletons(dir: root + "/Assets/configs/exoskeletons")
        )
    }
}
