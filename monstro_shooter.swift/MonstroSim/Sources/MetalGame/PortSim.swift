import Foundation
import CoreML
import simd

// Faithful Swift port of torchsim/env_torch.py `step` (single game, N=1). Reads the shared WorldConfig
// + the baked per-game schedule (exported by export_world.py) and drives BOTH the player and every
// monster via Core ML — exactly the canonical ruleset. Captures per-tick positions so the Python side
// can diff this trajectory against the torch reference (two-env parity). Step ORDER mirrors env_torch
// precisely (player obs pre-spawn; enemy obs post-spawn/pre-fire; contact uses pre-move distance).

struct WorldJSON: Codable {
    var dt, player_speed, player_half, player_radius, map_half, turn_rate, buffer, bullet_radius: Float
    var damage_interval, diagonal_factor, defense_min_floor, player_max_hp, dist_norm: Float
    var monster_speed_norm, monster_count_norm, bullet_norm, eps: Float
}

struct SchedJSON: Codable {
    var name: String, gid: String, M: Int, B: Int, ticks: Int, arena_half: Float
    var spawn_tick: [Float], offset: [[Float]], hp0: [Float], speed: [Float]
    var boxW: [Float], dmg: [Float], direct: [Float], type: [Int]
    var bullet_speed, bullet_damage, bullet_range: Float
    var fire_interval, contact_interval: Int, defense: Float
    var bullets_per_shot, penetration, mag_size, reload_ticks: Int
    var max_dev, exo_speed: Float
}

/// deterministic spread rand in [-1,1] from (tick, pellet) — identical to env_torch.det_rand
func detRand(_ t: Int, _ k: Int) -> Float {
    let h = (t &* 2654435761 &+ k &* 340573 &+ 12345) & 0xffffffff
    return Float(Double(h) / 2147483647.5 - 1.0)
}

/// Generic Core ML net: obs [Float] -> action [Float]. Input feature "obs", output "action".
final class CoreMLNet {
    private let model: MLModel
    init?(path: String) {
        guard let compiled = try? MLModel.compileModel(at: URL(fileURLWithPath: path)) else { return nil }
        let cfg = MLModelConfiguration(); cfg.computeUnits = .all
        guard let m = try? MLModel(contentsOf: compiled, configuration: cfg) else { return nil }
        model = m
    }
    func predict(_ obs: [Float]) -> [Float] {
        guard let arr = try? MLMultiArray(shape: [NSNumber(value: obs.count)], dataType: .float32) else { return [] }
        for (i, v) in obs.enumerated() { arr[i] = NSNumber(value: v) }
        guard let prov = try? MLDictionaryFeatureProvider(dictionary: ["obs": MLFeatureValue(multiArray: arr)]),
              let out = try? model.prediction(from: prov),
              let o = out.featureValue(for: "action")?.multiArrayValue else { return [] }
        return (0..<o.count).map { o[$0].floatValue }
    }
}

final class PortSim {
    let w: WorldJSON
    let s: SchedJSON
    let player: CoreMLNet?       // nil in the playable game (human moves the player)
    let enemy: CoreMLNet
    let M: Int, B: Int
    let mapHalf: Float

    // state
    var playerPos = SIMD2<Float>(0, 0)
    var playerHP: Float
    var monPos: [SIMD2<Float>]
    var monVel: [SIMD2<Float>]
    var monHP: [Float]
    var monAct: [Float]
    var bulPos: [SIMD2<Float>]
    var bulVel: [SIMD2<Float>]
    var bulAlive: [Float]
    var bulDist: [Float]
    var bulPen: [Float]
    var monContact: [Float]
    var ammo: Float
    var reloadT: Float = 0
    var lastAim = SIMD2<Float>(0, 1)     // player aim this tick (for sprite facing)
    var kills = 0
    let offset: [SIMD2<Float>]

    init(w: WorldJSON, s: SchedJSON, player: CoreMLNet?, enemy: CoreMLNet) {
        self.w = w; self.s = s; self.player = player; self.enemy = enemy
        M = s.M; B = s.B; mapHalf = s.arena_half
        playerHP = w.player_max_hp
        monPos = Array(repeating: .zero, count: M)
        monVel = Array(repeating: .zero, count: M)
        monHP = s.hp0
        monAct = Array(repeating: 0, count: M)
        bulPos = Array(repeating: .zero, count: B)
        bulVel = Array(repeating: .zero, count: B)
        bulAlive = Array(repeating: 0, count: B)
        bulDist = Array(repeating: 0, count: B)
        bulPen = Array(repeating: 0, count: B)
        monContact = Array(repeating: 0, count: M)
        ammo = Float(s.mag_size)
        offset = s.offset.map { SIMD2<Float>($0[0], $0[1]) }
    }

    // player obs (8) — from PRE-spawn state, mirrors env_torch.player_obs_vec
    private func playerObs() -> [Float] {
        let eps = w.eps
        var cnt: Float = 0, nearest: Float = 1e9, sumDist: Float = 0
        var threat = SIMD2<Float>(0, 0)
        for m in 0..<M {
            let rel = monPos[m] - playerPos                 // toward monster
            let dist = simd_length(rel) + eps
            let alive: Float = (monAct[m] > 0.5 && monHP[m] > 0) ? 1 : 0
            cnt += alive
            threat += (rel / dist) * alive
            sumDist += dist * alive
            if alive > 0.5 && dist < nearest { nearest = dist }
        }
        let tl = simd_length(threat)
        let threatN = tl > eps ? threat / (tl + eps) : SIMD2<Float>(0, 0)
        let meanD = sumDist / (cnt + eps)
        let wall = playerPos / mapHalf
        return [playerHP / w.player_max_hp, cnt / w.monster_count_norm, threatN.x, threatN.y,
                nearest / w.dist_norm, meanD / w.dist_norm, wall.x, wall.y]
    }

    // enemy obs (10) for monster m — post-spawn/pre-fire, mirrors env_torch.enemy_obs_vec
    private func enemyObs(_ m: Int) -> [Float] {
        let eps = w.eps
        let rel = playerPos - monPos[m]                     // toward player
        let dist = simd_length(rel) + eps
        let dirv = rel / dist
        let spd = s.speed[m]
        let velN = monVel[m] / (spd + eps)
        var bmin: Float = 1e18, bidx = -1
        for b in 0..<B where bulAlive[b] > 0.5 {
            let d = bulPos[b] - monPos[m]
            let d2 = simd_dot(d, d)
            if d2 < bmin { bmin = d2; bidx = b }
        }
        var bdir = SIMD2<Float>(0, 0); var bdistN: Float = 2
        if bmin < 1e17 && bidx >= 0 {
            let bdist = sqrtf(max(bmin, 0)) + eps
            bdir = (bulPos[bidx] - monPos[m]) / bdist
            bdistN = min(bdist / w.bullet_norm, 2)
        }
        return [dirv.x, dirv.y, dist / w.dist_norm, velN.x, velN.y, spd / w.monster_speed_norm,
                monHP[m] / (s.hp0[m] + eps), bdir.x, bdir.y, bdistN]
    }

    func step(_ t: Int) {                              // parity / training: player driven by Core ML
        let pa = player?.predict(playerObs()) ?? []
        core(t, SIMD2<Float>(pa.count > 1 ? pa[0] : 0, pa.count > 1 ? pa[1] : 0),
             SIMD2<Float>(pa.count > 3 ? pa[2] : 0, pa.count > 3 ? pa[3] : 1))
    }

    // playable game: human move + auto-aim at nearest monster (monsters still driven by Core ML)
    func stepGame(_ t: Int, _ humanMove: SIMD2<Float>) { core(t, humanMove, nearestVec()) }

    func nearestVec() -> SIMD2<Float> {
        var best: Float = 1e18, v = SIMD2<Float>(0, 1)
        for m in 0..<M where monAct[m] > 0.5 && monHP[m] > 0 {
            let d = monPos[m] - playerPos; let dd = simd_dot(d, d)
            if dd < best { best = dd; v = d }
        }
        return v
    }

    func core(_ t: Int, _ aMove: SIMD2<Float>, _ aAim: SIMD2<Float>) {
        let eps = w.eps, dt = w.dt
        var aim = aAim

        // 2) spawn (relative to current player pos)
        let elapsed = Float(t) * dt
        for m in 0..<M where s.spawn_tick[m] <= elapsed && monAct[m] < 0.5 {
            monPos[m] = playerPos + offset[m]; monAct[m] = 1
        }

        // 3) per-monster: enemy net velocity (uses post-spawn pos, pre-fire bullets); save PRE-move dist
        var distPre = [Float](repeating: 0, count: M)
        for m in 0..<M {
            let due = s.spawn_tick[m] <= elapsed
            let aliveB = due && monHP[m] > 0
            let rel = playerPos - monPos[m]
            let dist = simd_length(rel) + eps
            distPre[m] = dist
            let stop = w.player_radius + s.boxW[m] / 2
            let moveMask = (aliveB && dist > stop)
            if moveMask {
                let ea = enemy.predict(enemyObs(m))
                let v = SIMD2<Float>(tanhf(ea.count > 1 ? ea[0] : 0), tanhf(ea.count > 1 ? ea[1] : 0))
                let vn = v / (simd_length(v) + eps)
                monVel[m] = vn * s.speed[m]
            } else {
                monVel[m] = .zero
            }
            monPos[m] += monVel[m] * dt
        }

        // 4) ammo/reload + fire bulletsPerShot pellets (deterministic spread)
        let an = simd_length(aim); aim = an > eps ? aim / (an + eps) : SIMD2<Float>(0, 1)
        lastAim = aim
        let wasReloading = reloadT > 0
        reloadT = max(reloadT - 1, 0)
        if wasReloading && reloadT == 0 { ammo = Float(s.mag_size) }
        if t % s.fire_interval == 0 && ammo > 0 && reloadT == 0 {
            ammo -= 1
            if ammo <= 0 { reloadT = Float(s.reload_ticks) }
            let shot = t / s.fire_interval
            for k in 0..<s.bullets_per_shot {
                let slot = (shot * s.bullets_per_shot + k) % B
                let theta = atan2f(s.max_dev * detRand(t, k), 500)
                let ct = cosf(theta), st = sinf(theta)
                let pa = SIMD2<Float>(aim.x * ct - aim.y * st, aim.x * st + aim.y * ct)
                bulPos[slot] = playerPos; bulVel[slot] = pa * s.bullet_speed
                bulAlive[slot] = 1; bulDist[slot] = 0; bulPen[slot] = Float(s.penetration)
            }
        }
        // 5) move bullets, expire by range
        for b in 0..<B {
            bulPos[b] += bulVel[b] * dt
            bulDist[b] += simd_length(bulVel[b]) * dt
            if bulAlive[b] > 0.5 && bulDist[b] >= s.bullet_range { bulAlive[b] = 0 }
        }
        // 6) collision with penetration (bullet damages every overlap; dies after `pen` hits)
        var aliveB = [Bool](repeating: false, count: M)
        for m in 0..<M { aliveB[m] = (s.spawn_tick[m] <= elapsed) && monHP[m] > 0 }
        for b in 0..<B where bulAlive[b] > 0.5 {
            var hits: Float = 0
            for m in 0..<M where aliveB[m] {
                let hitR = w.bullet_radius + s.boxW[m] / 2
                let d = bulPos[b] - monPos[m]
                if simd_dot(d, d) < hitR * hitR { monHP[m] -= s.bullet_damage; hits += 1 }
            }
            bulPen[b] -= hits
            if bulPen[b] <= 0 { bulAlive[b] = 0 }
        }
        // 7) kills
        var killed = 0
        for m in 0..<M where aliveB[m] && !(monHP[m] > 0) { killed += 1 }
        kills += killed
        // 8) contact: immediate pulse on newly-touching + periodic for sustained; defense + min floor
        let gateC: Float = (t % s.contact_interval == 0) ? 1 : 0
        var dmg: Float = 0
        for m in 0..<M {
            let aliveA = (s.spawn_tick[m] <= elapsed) && monHP[m] > 0
            let now: Float = (aliveA && distPre[m] < (w.player_radius + s.boxW[m] / 2 + w.buffer)) ? 1 : 0
            dmg += (now * (1 - monContact[m]) + now * monContact[m] * gateC) * s.dmg[m]
            monContact[m] = now
        }
        if dmg > 0 { playerHP -= max(dmg - s.defense, w.defense_min_floor) }
        // 9) player move (tanh, exo speed, per-arena clamp)
        let mv = SIMD2<Float>(tanhf(aMove.x), tanhf(aMove.y))
        let lo = -mapHalf + w.player_half, hi = mapHalf - w.player_half
        playerPos += mv * (w.player_speed * s.exo_speed * dt)
        playerPos = simd_clamp(playerPos, SIMD2<Float>(lo, lo), SIMD2<Float>(hi, hi))
    }
}

// ---- parity runner: replay the 9 exported games through the Swift port, dump positions ----
struct IndexJSON: Codable { var games: [String]; var bullets: Int }
struct FrameOut: Codable {
    var t: Int; var player: [Float]; var mon_alive: [Int]; var mon_pos: [Float]
    var bul_alive: [Int]; var bul_pos: [Float]; var kills: Int; var hp: Float
}

func runPort() {
    let args = CommandLine.arguments
    func val(_ k: String, _ d: String) -> String {
        if let i = args.firstIndex(of: k), i + 1 < args.count { return args[i + 1] }; return d
    }
    let dir = val("--port", "parity")
    let playerPath = val("--player", "\(dir)/../../MonstroSim/models/player.mlmodel")
    let enemyPath = val("--enemy", "\(dir)/../../MonstroSim/models/monster.mlmodel")
    guard let player = CoreMLNet(path: playerPath), let enemy = CoreMLNet(path: enemyPath) else {
        FileHandle.standardError.write("port: failed to load Core ML models (\(playerPath), \(enemyPath))\n".data(using: .utf8)!)
        exit(1)
    }
    let dec = JSONDecoder(), enc = JSONEncoder()
    func load<T: Decodable>(_ p: String) -> T { try! dec.decode(T.self, from: Data(contentsOf: URL(fileURLWithPath: p))) }
    let idx: IndexJSON = load("\(dir)/index.json")
    let world: WorldJSON = load("\(dir)/world.json")
    for gid in idx.games {
        let sched: SchedJSON = load("\(dir)/sched_\(gid).json")
        let sim = PortSim(w: world, s: sched, player: player, enemy: enemy)
        var frames: [FrameOut] = []
        for t in 1...sched.ticks {
            sim.step(t)
            let alive = (0..<sim.M).map { (sim.monAct[$0] > 0.5 && sim.monHP[$0] > 0) ? 1 : 0 }
            frames.append(FrameOut(t: t, player: [sim.playerPos.x, sim.playerPos.y],
                                   mon_alive: alive, mon_pos: sim.monPos.flatMap { [$0.x, $0.y] },
                                   bul_alive: sim.bulAlive.map { $0 > 0.5 ? 1 : 0 },
                                   bul_pos: sim.bulPos.flatMap { [$0.x, $0.y] },
                                   kills: sim.kills, hp: sim.playerHP))
            if sim.playerHP <= 0 || sim.kills >= sim.M { break }
        }
        try! enc.encode(frames).write(to: URL(fileURLWithPath: "\(dir)/swift_\(gid).json"))
        print("  \(gid): ticks=\(frames.count) kills=\(sim.kills) hp=\(Int(max(sim.playerHP, 0)))")
    }
    print("wrote swift_*.json -> \(dir)/")
}
