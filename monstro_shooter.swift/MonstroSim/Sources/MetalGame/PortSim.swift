import Foundation
import simd
import MLX

// Loop-free Swift port of torchsim/env_torch.py `step` (single game). Every per-entity operation is an
// MLX tensor op on the Metal GPU — NO Swift `for` loop over monsters or bullets. Both the player and the
// shared enemy net are in-graph MLX MLPs (matmul+relu over [M,10]/[1,8]), so the whole tick — spawn,
// steering, multi-pellet fire, penetrating collision, contact damage, player move — is one fused GPU
// graph. Step ORDER mirrors env_torch precisely. After each tick the state is materialized to plain Swift
// arrays (one host readback) for the sprite renderer. The only loops left are the per-tick time loop (in
// Game/runPort) and the 2-layer MLP-depth loop (network layers, not entities).

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

/// In-graph MLP loaded from the shared {sizes,w,b} JSON (same file Core ML exports from). Weights [in,out],
/// relu on hidden layers, linear out — mirrors torchsim/policy_torch.py::apply_mlp exactly. Batched: an
/// [M,in] input runs all M monsters in one matmul.
final class MLXMLP {
    struct NetJSON: Codable { var sizes: [Int]; var w: [[Float]]; var b: [[Float]] }
    private var W: [MLXArray] = []
    private var bias: [MLXArray] = []
    init?(path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let d = try? JSONDecoder().decode(NetJSON.self, from: data) else { return nil }
        for i in 0..<d.w.count {
            W.append(MLXArray(d.w[i], [d.sizes[i], d.sizes[i + 1]]))
            bias.append(MLXArray(d.b[i], [d.sizes[i + 1]]))
        }
    }
    func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = x
        let n = W.count
        for i in 0..<n {                       // MLP-depth loop (network layers, not entities)
            h = matmul(h, W[i]) + bias[i]
            if i < n - 1 { h = maximum(h, MLXArray(0.0)) }
        }
        return h
    }
}

final class PortSim {
    let w: WorldJSON
    let s: SchedJSON
    let player: MLXMLP?          // nil in the playable game (human moves the player)
    let enemy: MLXMLP
    let M: Int, B: Int
    let mapHalf: Float

    // ---- MLX state (single game; shapes mirror env_torch with the P,N dims dropped) ----
    private var mPlayerPos: MLXArray          // [2]
    private var mPlayerHP: MLXArray           // [1]
    private var mMonPos: MLXArray             // [M,2]
    private var mMonVel: MLXArray             // [M,2]
    private var mMonHP: MLXArray              // [M]
    private var mMonAct: MLXArray             // [M]
    private var mMonContact: MLXArray         // [M]
    private var mBulPos: MLXArray             // [B,2]
    private var mBulVel: MLXArray             // [B,2]
    private var mBulAlive: MLXArray           // [B]
    private var mBulDist: MLXArray            // [B]
    private var mBulPen: MLXArray             // [B]
    private var mAmmo: MLXArray               // [1]
    private var mReloadT: MLXArray            // [1]
    private var mLastAim: MLXArray            // [2]
    // constant schedule tensors
    private let cSpawn: MLXArray, cOffset: MLXArray, cHP0: MLXArray, cSpeed: MLXArray
    private let cBoxW: MLXArray, cDmg: MLXArray

    // ---- host mirrors for the renderer (materialized each tick straight from .asArray — NO loops) ----
    var playerPos = SIMD2<Float>(0, 0)
    var playerHP: Float
    var monPosF: [Float] = [], monVelF: [Float] = []   // flat [x0,y0,x1,y1,...]; renderer indexes via accessors
    var bulPosF: [Float] = [], bulVelF: [Float] = []
    var monHP: [Float] = []
    var monAct: [Float] = []
    var bulAlive: [Float] = []
    var lastAim = SIMD2<Float>(0, 1)
    var kills = 0
    // index accessors (read by the render loop, which already iterates sprites — not the inference path)
    func monPos(_ i: Int) -> SIMD2<Float> { SIMD2(monPosF[2 * i], monPosF[2 * i + 1]) }
    func monVel(_ i: Int) -> SIMD2<Float> { SIMD2(monVelF[2 * i], monVelF[2 * i + 1]) }
    func bulPos(_ i: Int) -> SIMD2<Float> { SIMD2(bulPosF[2 * i], bulPosF[2 * i + 1]) }
    func bulVel(_ i: Int) -> SIMD2<Float> { SIMD2(bulVelF[2 * i], bulVelF[2 * i + 1]) }

    private let eps: Float = 1e-6

    init(w: WorldJSON, s: SchedJSON, player: MLXMLP?, enemy: MLXMLP) {
        self.w = w; self.s = s; self.player = player; self.enemy = enemy
        M = s.M; B = s.B; mapHalf = s.arena_half
        playerHP = w.player_max_hp
        cSpawn = MLXArray(s.spawn_tick, [M])
        cOffset = MLXArray(s.offset.flatMap { $0 }, [M, 2])
        cHP0 = MLXArray(s.hp0, [M])
        cSpeed = MLXArray(s.speed, [M])
        cBoxW = MLXArray(s.boxW, [M])
        cDmg = MLXArray(s.dmg, [M])
        mPlayerPos = MLXArray.zeros([2])
        mPlayerHP = MLXArray([w.player_max_hp], [1])
        mMonPos = MLXArray.zeros([M, 2])
        mMonVel = MLXArray.zeros([M, 2])
        mMonHP = MLXArray(s.hp0, [M])
        mMonAct = MLXArray.zeros([M])
        mMonContact = MLXArray.zeros([M])
        mBulPos = MLXArray.zeros([B, 2])
        mBulVel = MLXArray.zeros([B, 2])
        mBulAlive = MLXArray.zeros([B])
        mBulDist = MLXArray.zeros([B])
        mBulPen = MLXArray.zeros([B])
        mAmmo = MLXArray([Float(s.mag_size)], [1])
        mReloadT = MLXArray.zeros([1])
        mLastAim = MLXArray([0, 1] as [Float], [2])
        sync()
    }

    // player obs (8) from PRE-spawn state — mirrors env_torch.player_obs_vec → [1,8]
    private func playerObs() -> MLXArray {
        let rel = mMonPos - mPlayerPos                                  // [M,2] toward monster
        let dist = sqrt((rel * rel).sum(axis: 1)) + eps                 // [M]
        let alive = which(logicalAnd(greater(mMonAct, 0.5), greater(mMonHP, 0)), MLXArray(1.0), MLXArray(0.0))
        let cnt = alive.sum()                                           // scalar
        let dirv = rel / dist.expandedDimensions(axis: 1)              // [M,2]
        let threat = (dirv * alive.expandedDimensions(axis: 1)).sum(axis: 0)  // [2]
        let threatN = threat / (sqrt((threat * threat).sum()) + eps)   // [2]
        let masked = which(greater(alive, 0.5), dist, MLXArray(1e9))
        let nearest = masked.min()                                     // scalar
        let meanD = (dist * alive).sum() / (cnt + eps)
        let wall = mPlayerPos / mapHalf                                // [2]
        let s1 = { (a: MLXArray) in a.reshaped([1]) }
        return concatenated([
            s1(mPlayerHP / w.player_max_hp),
            s1(cnt / w.monster_count_norm),
            threatN,
            s1(nearest / w.dist_norm),
            s1(meanD / w.dist_norm),
            wall,
        ], axis: 0).reshaped([1, 8])
    }

    // enemy obs (10) per monster — post-spawn/pre-fire, mirrors env_torch.enemy_obs_vec → [M,10]
    private func enemyObs() -> MLXArray {
        let rel = mPlayerPos - mMonPos                                 // [M,2] toward player
        let dist = sqrt((rel * rel).sum(axis: 1)) + eps                // [M]
        let dirv = rel / dist.expandedDimensions(axis: 1)             // [M,2]
        let velN = mMonVel / (cSpeed.expandedDimensions(axis: 1) + eps) // [M,2]
        let brel = mBulPos.expandedDimensions(axis: 0) - mMonPos.expandedDimensions(axis: 1) // [M,B,2]
        var bd2 = (brel * brel).sum(axis: 2)                           // [M,B]
        bd2 = which(greater(mBulAlive.expandedDimensions(axis: 0), 0.5), bd2, MLXArray(1e18))
        let bidx = bd2.argMin(axis: 1)                                 // [M]
        let idxB = broadcast(bidx.reshaped([M, 1, 1]), to: [M, 1, 2])
        let bnear = takeAlong(brel, idxB, axis: 1).squeezed(axis: 1)   // [M,2]
        let bmin = bd2.min(axis: 1)                                    // [M]
        let has = which(less(bmin, 1e17), MLXArray(1.0), MLXArray(0.0))// [M]
        let bdist = sqrt(maximum(bmin, MLXArray(0.0))) + eps          // [M]
        let bdir = bnear / bdist.expandedDimensions(axis: 1) * has.expandedDimensions(axis: 1)
        let bdistN = which(greater(has, 0.5), clip(bdist / w.bullet_norm, max: MLXArray(2.0)), MLXArray(2.0))
        let col = { (a: MLXArray) in a.expandedDimensions(axis: 1) }   // [M] -> [M,1]
        return concatenated([
            dirv,
            col(dist / w.dist_norm),
            velN,
            col(cSpeed / w.monster_speed_norm),
            col(mMonHP / (cHP0 + eps)),
            bdir,
            col(bdistN),
        ], axis: 1)                                                    // [M,10]
    }

    // parity / training: player driven by the net
    func step(_ t: Int) {
        if let p = player {
            let a = p(playerObs()).reshaped([4])                       // [moveX,moveY,aimX,aimY]
            core(t, a[0 ..< 2], a[2 ..< 4])
        } else {
            core(t, MLXArray([0, 0] as [Float], [2]), MLXArray([0, 1] as [Float], [2]))
        }
    }

    // playable game: human move + auto-aim at nearest monster (monsters still net-driven)
    func stepGame(_ t: Int, _ humanMove: SIMD2<Float>) {
        core(t, MLXArray([humanMove.x, humanMove.y], [2]), nearestVecMLX())
    }

    /// direction toward the nearest alive monster, as MLX [2] (no host loop: argMin + take)
    private func nearestVecMLX() -> MLXArray {
        let rel = mMonPos - mPlayerPos                                 // [M,2]
        let d2 = (rel * rel).sum(axis: 1)                              // [M]
        let masked = which(logicalAnd(greater(mMonAct, 0.5), greater(mMonHP, 0)), d2, MLXArray(1e18))
        let idx = masked.argMin()                                     // scalar
        let idxB = broadcast(idx.reshaped([1, 1]), to: [1, 2])
        return takeAlong(rel, idxB, axis: 0).reshaped([2])
    }

    /// host SIMD2 nearest direction (for the headless kite driver) — one argMin + readback, no loop
    func nearestVec() -> SIMD2<Float> {
        let v = nearestVecMLX(); eval(v); let a = v.asArray(Float.self)
        return SIMD2<Float>(a[0], a[1])
    }

    func core(_ t: Int, _ aMove: MLXArray, _ aAim: MLXArray) {
        let dt = w.dt
        let elapsed = Float(t) * dt

        // 2) spawn (relative to current player pos)
        let due = lessEqual(cSpawn, elapsed)                           // [M] bool
        let just = logicalAnd(due, less(mMonAct, 0.5))
        mMonPos = which(just.expandedDimensions(axis: 1), mPlayerPos + cOffset, mMonPos)
        mMonAct = maximum(mMonAct, which(just, MLXArray(1.0), MLXArray(0.0)))
        let aliveB = logicalAnd(due, greater(mMonHP, 0))               // [M] bool (pre-collision)

        // 3) per-monster enemy-net velocity (post-spawn pos, pre-fire bullets); PRE-move distance
        let rel = mPlayerPos - mMonPos                                 // [M,2]
        let distPre = sqrt((rel * rel).sum(axis: 1)) + eps            // [M]
        let stop = w.player_radius + cBoxW / 2                         // [M]
        let moveMask = which(logicalAnd(aliveB, greater(distPre, stop)), MLXArray(1.0), MLXArray(0.0))
        let ea = enemy(enemyObs())                                    // [M,2]
        let v = tanh(ea)
        let vn = v / (sqrt((v * v).sum(axis: 1, keepDims: true)) + eps)
        mMonVel = vn * cSpeed.expandedDimensions(axis: 1) * moveMask.expandedDimensions(axis: 1)
        mMonPos = mMonPos + mMonVel * dt

        // 4) ammo/reload + fire bulletsPerShot pellets (deterministic spread)
        let aim = aAim / (sqrt((aAim * aAim).sum()) + eps)            // [2]
        mLastAim = aim
        let reloadPrev = mReloadT
        mReloadT = maximum(reloadPrev - 1, MLXArray(0.0))
        let justReloaded = logicalAnd(greater(reloadPrev, 0), lessEqual(mReloadT, 0))
        mAmmo = which(justReloaded, MLXArray(Float(s.mag_size)), mAmmo)
        let gate = (t % s.fire_interval == 0)
        let fireF = gate
            ? which(logicalAnd(greater(mAmmo, 0), lessEqual(mReloadT, 0)), MLXArray(1.0), MLXArray(0.0))
            : MLXArray.zeros([1])
        mAmmo = mAmmo - fireF
        let needReload = logicalAnd(lessEqual(mAmmo, 0), lessEqual(mReloadT, 0))
        mReloadT = which(needReload, MLXArray(Float(s.reload_ticks)), mReloadT)

        // pellets vectorized over K — NO loop: det_rand(t,k) as an int64 hash + one-hot ring slots, all
        // MLX (matches env_torch's vectorized pellet scatter; `& 0xffffffff` == `% 2^32` for this hash > 0).
        let K = s.bullets_per_shot
        let shot = t / s.fire_interval
        let kIdx = MLXArray.arange(K, dtype: .int64)                  // [K]
        let hbase = Int(t) * 2654435761 + 12345
        let hsh = (kIdx * 340573 + hbase) % 4294967296               // [K] int64 det_rand hash
        let dr = hsh.asType(.float32) / 2147483647.5 - 1.0           // [K] in [-1,1]
        let theta = atan2(s.max_dev * dr, MLXArray(Float(500)))      // [K]
        let ctA = cos(theta), stA = sin(theta)                       // [K]
        let slots = (kIdx + (shot * K)) % B                          // [K] int64 ring slots
        let bIdx = MLXArray.arange(B, dtype: .int64)                 // [B]
        let oh = which(equal(slots.expandedDimensions(axis: 1), bIdx.expandedDimensions(axis: 0)),
                       MLXArray(1.0), MLXArray(0.0))                  // [K,B]
        let ax = aim[0], ay = aim[1]
        let paX = ax * ctA - ay * stA, paY = ax * stA + ay * ctA      // [K]
        let velK = stacked([paX, paY], axis: 1) * s.bullet_speed       // [K,2]
        let velB = matmul(oh.transposed(), velK)                       // [B,2]
        let writeB = clip(oh.sum(axis: 0), max: MLXArray(1.0)) * fireF // [B]
        let wcol = writeB.expandedDimensions(axis: 1)
        mBulPos = which(greater(wcol, 0.5), broadcast(mPlayerPos, to: [B, 2]), mBulPos)
        mBulVel = which(greater(wcol, 0.5), velB, mBulVel)
        mBulAlive = which(greater(writeB, 0.5), MLXArray(1.0), mBulAlive)
        mBulDist = which(greater(writeB, 0.5), MLXArray(0.0), mBulDist)
        mBulPen = which(greater(writeB, 0.5), MLXArray(Float(s.penetration)), mBulPen)

        // 5) move bullets, expire by range
        mBulPos = mBulPos + mBulVel * dt
        mBulDist = mBulDist + sqrt((mBulVel * mBulVel).sum(axis: 1)) * dt
        mBulAlive = which(logicalAnd(greater(mBulAlive, 0.5), less(mBulDist, s.bullet_range)),
                          MLXArray(1.0), MLXArray(0.0))

        // 6) collision with penetration (bullet damages every overlap; dies after `pen` hits)
        let diff = mBulPos.expandedDimensions(axis: 1) - mMonPos.expandedDimensions(axis: 0) // [B,M,2]
        let d2 = (diff * diff).sum(axis: 2)                           // [B,M]
        let hitR = w.bullet_radius + cBoxW / 2                         // [M]
        let hitRsq = (hitR * hitR).expandedDimensions(axis: 0)       // [1,M]
        let hitMask = logicalAnd(logicalAnd(less(d2, hitRsq),
                                            greater(mBulAlive, 0.5).expandedDimensions(axis: 1)),
                                 aliveB.expandedDimensions(axis: 0))  // [B,M]
        let hitF = which(hitMask, MLXArray(1.0), MLXArray(0.0))
        mMonHP = mMonHP - (hitF * s.bullet_damage).sum(axis: 0)       // [M]
        mBulPen = mBulPen - hitF.sum(axis: 1)                         // [B]
        mBulAlive = which(logicalAnd(greater(mBulAlive, 0.5), greater(mBulPen, 0.5)),
                          MLXArray(1.0), MLXArray(0.0))

        // 7) kills
        let aliveA = logicalAnd(due, greater(mMonHP, 0))
        let killed = which(logicalAnd(aliveB, logicalNot(aliveA)), MLXArray(1.0), MLXArray(0.0)).sum()
        eval(killed); kills += Int(killed.item(Float.self))

        // 8) contact: immediate pulse on newly-touching + periodic for sustained; defense + min floor
        let gateC: Float = (t % s.contact_interval == 0) ? 1 : 0
        let contactNow = which(logicalAnd(aliveA, less(distPre, w.player_radius + cBoxW / 2 + w.buffer)),
                               MLXArray(1.0), MLXArray(0.0))           // [M]
        let newly = contactNow * (1 - mMonContact)
        let sustained = contactNow * mMonContact
        let dmg = ((newly + sustained * gateC) * cDmg).sum()          // scalar
        let applied = which(greater(dmg, 0), clip(dmg - s.defense, min: MLXArray(w.defense_min_floor)), MLXArray(0.0))
        mPlayerHP = mPlayerHP - applied
        mMonContact = contactNow

        // 9) player move (tanh, exo speed, per-arena clamp)
        let mv = tanh(aMove)
        let lo = -mapHalf + w.player_half, hi = mapHalf - w.player_half
        mPlayerPos = clip(mPlayerPos + mv * (w.player_speed * s.exo_speed * dt),
                          min: MLXArray(lo), max: MLXArray(hi))

        sync()
    }

    /// materialize MLX state into the host arrays the renderer reads (one GPU readback per tick)
    private func sync() {
        eval(mPlayerPos, mPlayerHP, mMonPos, mMonVel, mMonHP, mMonAct, mBulPos, mBulVel, mBulAlive, mLastAim)
        let pp = mPlayerPos.asArray(Float.self); playerPos = SIMD2(pp[0], pp[1])
        playerHP = mPlayerHP.asArray(Float.self)[0]
        let la = mLastAim.asArray(Float.self); lastAim = SIMD2(la[0], la[1])
        monPosF = mMonPos.asArray(Float.self); monVelF = mMonVel.asArray(Float.self)
        monHP = mMonHP.asArray(Float.self); monAct = mMonAct.asArray(Float.self)
        bulPosF = mBulPos.asArray(Float.self); bulVelF = mBulVel.asArray(Float.self)
        bulAlive = mBulAlive.asArray(Float.self)
    }
}

// ---- parity runner: replay the exported games through the MLX port, dump positions ----
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
    let playerPath = val("--player", "\(dir)/../../MonstroSim/models/player.json")
    let enemyPath = val("--enemy", "\(dir)/../../MonstroSim/models/monster.json")
    guard let player = MLXMLP(path: playerPath), let enemy = MLXMLP(path: enemyPath) else {
        FileHandle.standardError.write("port: failed to load MLX nets (\(playerPath), \(enemyPath))\n".data(using: .utf8)!)
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
                                   mon_alive: alive, mon_pos: sim.monPosF,
                                   bul_alive: sim.bulAlive.map { $0 > 0.5 ? 1 : 0 },
                                   bul_pos: sim.bulPosF,
                                   kills: sim.kills, hp: sim.playerHP))
            if sim.playerHP <= 0 || sim.kills >= sim.M { break }
        }
        try! enc.encode(frames).write(to: URL(fileURLWithPath: "\(dir)/swift_\(gid).json"))
        print("  \(gid): ticks=\(frames.count) kills=\(sim.kills) hp=\(Int(max(sim.playerHP, 0)))")
    }
    print("wrote swift_*.json -> \(dir)/")
}
