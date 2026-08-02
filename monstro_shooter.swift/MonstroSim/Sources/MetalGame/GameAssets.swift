import Foundation
import simd

// Self-contained loading so the Metal game runs WITHOUT the Python export: flat-YAML config parsing,
// map JSON, native spawn-schedule generation (mirrors torchsim/schedule.py logic), and the default
// WorldConfig. The schedule layout need not bit-match torch (parity uses the shared exported schedule);
// the playable game generates its own.

struct SplitMix64 {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func uniform(_ lo: Float, _ hi: Float) -> Float {
        let r = Float(next() >> 11) / Float(UInt64(1) << 53)
        return lo + (hi - lo) * r
    }
    mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
}

/// minimal flat "key: value" YAML (the monster/weapon/exo configs are flat scalars)
func parseFlatYAML(_ path: String) -> [String: String] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
    var d: [String: String] = [:]
    for raw in text.split(separator: "\n") {
        let l = raw.trimmingCharacters(in: .whitespaces)
        if l.isEmpty || l.hasPrefix("#") || l.hasPrefix("-") { continue }
        guard let c = l.firstIndex(of: ":") else { continue }
        let key = String(l[l.startIndex..<c]).trimmingCharacters(in: .whitespaces)
        let val = String(l[l.index(after: c)...]).trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        if !val.isEmpty && !val.contains(":") { d[key] = val }   // skip nested block headers
    }
    return d
}

struct MonCfg { var speed, boxW, health, damage: Float; var direct: Bool; var folder: String; var rotOffset: Float }

func loadMonsters(_ dir: String) -> [Int: MonCfg] {
    var out: [Int: MonCfg] = [:]
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return out }
    for f in files where f.hasSuffix(".yaml") {
        let y = parseFlatYAML("\(dir)/\(f)")
        guard let tid = y["monsterTypeID"].flatMap({ Int($0) }) else { continue }
        out[tid] = MonCfg(speed: Float(y["speed"] ?? "") ?? 100, boxW: Float(y["boxWidth"] ?? "") ?? 44,
                          health: Float(y["health"] ?? "") ?? 4, damage: Float(y["damage"] ?? "") ?? 2,
                          direct: (y["useDirectSteering"] ?? "true") == "true",
                          folder: String(f.dropLast(5)),
                          // per-type sprite facing correction (the Walk atlas's default orientation);
                          // SteeringMath uses atan2(vy,vx) + rotationOffset. 0 for Bug/Bird/etc.
                          rotOffset: Float(y["rotationOffset"] ?? "") ?? .pi / 4)
    }
    return out
}

func loadByID(_ dir: String) -> [Int: [String: String]] {
    var out: [Int: [String: String]] = [:]
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return out }
    for f in files where f.hasSuffix(".yaml") {
        let y = parseFlatYAML("\(dir)/\(f)")
        if let id = y["id"].flatMap({ Int($0) }) { out[id] = y }
    }
    return out
}

struct MapWave: Codable { var startTime: Int; var count: Int }
struct MapTypes: Codable { var startTime: Int; var monsterTypeIds: [Int] }
struct MapJSON: Codable {
    var id: Int?; var landingDuration: Float?; var arenaHalf: Float?; var spawnRadius: Float?
    var monsterSpawnWaves: [MapWave]; var monsterTypes: [MapTypes]
}

func defaultWorld() -> WorldJSON {
    WorldJSON(dt: 1.0 / 30, player_speed: 300, player_half: 30, player_radius: 30, map_half: 6000,
              turn_rate: 34, buffer: 5, bullet_radius: 6, damage_interval: 1, diagonal_factor: 0.75,
              defense_min_floor: 0.4, player_max_hp: 100, dist_norm: 1000, monster_speed_norm: 300,
              monster_count_norm: 64, bullet_norm: 1000, eps: 1e-6)
}

/// generate a SchedJSON natively from a map + the game configs (no Python).
func generateSched(mapPath: String, clientRoot: String, bullets: Int, seed: UInt64, dt: Float)
    -> (SchedJSON, [Int: String], [Int: Float])? {
    guard let map = try? JSONDecoder().decode(MapJSON.self, from: Data(contentsOf: URL(fileURLWithPath: mapPath)))
    else { return nil }
    let monsters = loadMonsters("\(clientRoot)/Assets/configs/monsters")
    let weapons = loadByID("\(clientRoot)/Assets/configs/weapons")
    let exos = loadByID("\(clientRoot)/Assets/configs/exoskeletons")
    let weapon = weapons[1] ?? weapons[2] ?? weapons.values.first ?? [:]
    let exo = exos[1] ?? exos.values.first ?? [:]
    let allTypes = map.monsterTypes.flatMap { $0.monsterTypeIds }
    if allTypes.isEmpty { return nil }
    let shw = map.spawnRadius ?? 830, shh = map.spawnRadius ?? 650
    let total = map.monsterSpawnWaves.reduce(0) { $0 + max($1.count, 0) }
    let M = max(min(total, 1024), 1)

    var spawn = [Float](repeating: 1e30, count: M), off = [[Float]](repeating: [0, 0], count: M)
    var hp0 = [Float](repeating: 1, count: M), speed = [Float](repeating: 0, count: M)
    var boxW = [Float](repeating: 1, count: M), dmg = [Float](repeating: 0, count: M)
    var direct = [Float](repeating: 1, count: M), type = [Int](repeating: 0, count: M)
    var rng = SplitMix64(seed)
    var slot = 0
    outer: for wave in map.monsterSpawnWaves {
        for k in 0..<wave.count {
            if slot >= M { break outer }
            let typ = allTypes[rng.int(allTypes.count)]
            let side = rng.int(4)
            var ox: Float = 0, oy: Float = 0
            switch side {
            case 0: ox = rng.uniform(-shw, shw); oy = shh
            case 1: ox = shw; oy = rng.uniform(-shh, shh)
            case 2: ox = rng.uniform(-shw, shw); oy = -shh
            default: ox = -shw; oy = rng.uniform(-shh, shh)
            }
            spawn[slot] = Float(wave.startTime) + Float(k) * 1.0
            off[slot] = [ox, oy]; type[slot] = typ
            if let m = monsters[typ] {
                hp0[slot] = m.health; speed[slot] = m.speed; boxW[slot] = m.boxW
                dmg[slot] = m.damage; direct[slot] = m.direct ? 1 : 0
            }
            slot += 1
        }
    }
    func wf(_ k: String, _ d: Float) -> Float { Float(weapon[k] ?? "") ?? d }
    func wi(_ k: String, _ d: Int) -> Int { Int(weapon[k] ?? "") ?? d }
    let sched = SchedJSON(
        name: (map.id.map { "map\($0)" }) ?? "map", gid: "game", M: M, B: bullets,
        ticks: Int((map.landingDuration ?? 60) * 30), arena_half: map.arenaHalf ?? 6000,
        spawn_tick: spawn, offset: off, hp0: hp0, speed: speed, boxW: boxW, dmg: dmg, direct: direct, type: type,
        bullet_speed: wf("bulletSpeed", 800), bullet_damage: wf("damage", 10), bullet_range: wf("shotRange", 500),
        fire_interval: max(1, Int((wf("shotDelay", 0.35) / dt).rounded())),
        contact_interval: max(1, Int((1.0 / dt).rounded())), defense: Float(exo["defence"] ?? "") ?? 0,
        bullets_per_shot: wi("bulletsPerShot", 1), penetration: max(1, wi("penetrationPower", 1)),
        mag_size: wi("magazineSize", 1_000_000), reload_ticks: max(1, Int(((Float(weapon["reloadTime"] ?? "") ?? 0) / dt).rounded())),
        max_dev: wf("maxDeviation", wf("bulletDeviation", 0)), exo_speed: Float(exo["speed"] ?? "") ?? 1)
    let folders = Dictionary(uniqueKeysWithValues: monsters.map { ($0.key, $0.value.folder) })
    let rotOffsets = Dictionary(uniqueKeysWithValues: monsters.map { ($0.key, $0.value.rotOffset) })
    return (sched, folders, rotOffsets)
}
