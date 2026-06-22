import Foundation
import simd
import MLX

// Batched (N games at once) MLX port of env_torch — plays the whole grid in ONE GPU rollout, exactly the
// way training rolls N envs. It mirrors PortSim.core with a leading [N] batch dim on every tensor, then
// records a per-tick replay "script" (positions + velocities + alive, per game) that a renderer just
// plays back. No per-game loop in the sim; the only loops are the time loop and host-side capture/setup.

/// one captured replay frame for all N games (flat row-major arrays)
struct GridFrame {
    var player: [Float]      // [N*2]
    var playerAim: [Float]   // [N*2]
    var monPos: [Float]      // [N*M*2]
    var monVel: [Float]      // [N*M*2]
    var monAlive: [Float]    // [N*M]
    var bulPos: [Float]      // [N*B*2]
    var bulVel: [Float]      // [N*B*2]
    var bulAlive: [Float]    // [N*B]
    var kills: [Float]       // [N]
    var hp: [Float]          // [N]
}

final class GridSim {
    let N: Int, M: Int, B: Int
    let w: WorldJSON
    private let player: MLXMLP
    private let enemy: MLXMLP
    let arenaHalf: [Float]            // [N]  per-game arena half-size
    let monType: [[Int]]             // [N][M] monster type id (for sprite slice)
    let monBox: [[Float]]            // [N][M] monster hitbox width (for sprite size)
    let ticks: Int

    // per-game weapon/exo scalars (identical across the grid — taken from game 0)
    private let bulletSpeed, bulletDamage, bulletRange, defense, maxDev, exoSpeed: Float
    private let fireInterval, contactInterval, bulletsPerShot, penetration, magSize, reloadTicks: Int

    // constant schedule tensors [N,M] / [N,M,2] / [N]
    private let cSpawn, cOffset, cHP0, cSpeed, cBoxW, cDmg, cArena: MLXArray

    // state [N,...]
    private var pPos, pHP, pAim, mPos, mVel, mHP, mAct, mContact: MLXArray
    private var bPos, bVel, bAlive, bDist, bPen, ammo, reloadT: MLXArray
    private var kills: MLXArray

    private let eps: Float = 1e-6

    init(w: WorldJSON, scheds: [SchedJSON], player: MLXMLP, enemy: MLXMLP) {
        self.w = w; self.player = player; self.enemy = enemy
        let nn = scheds.count                                  // locals (no self) so the packers are init-safe
        let mc = scheds.map { $0.M }.max() ?? 1
        let bb = scheds[0].B
        N = nn; M = mc; B = bb
        ticks = scheds.map { $0.ticks }.max() ?? 0
        let s0 = scheds[0]
        bulletSpeed = s0.bullet_speed; bulletDamage = s0.bullet_damage; bulletRange = s0.bullet_range
        defense = s0.defense; maxDev = s0.max_dev; exoSpeed = s0.exo_speed
        fireInterval = s0.fire_interval; contactInterval = s0.contact_interval
        bulletsPerShot = s0.bullets_per_shot; penetration = s0.penetration
        magSize = s0.mag_size; reloadTicks = s0.reload_ticks

        // pad each game's per-monster arrays to the common M and stack to [N,M] (never-spawn defaults)
        func packM(_ pick: (SchedJSON) -> [Float], _ pad: Float) -> MLXArray {
            var flat = [Float](repeating: pad, count: nn * mc)
            for g in 0..<nn { let a = pick(scheds[g]); for i in 0..<a.count { flat[g * mc + i] = a[i] } }
            return MLXArray(flat, [nn, mc])
        }
        cSpawn = packM({ $0.spawn_tick }, 1e30)
        cHP0 = packM({ $0.hp0 }, 1)
        cSpeed = packM({ $0.speed }, 0)
        cBoxW = packM({ $0.boxW }, 1)
        cDmg = packM({ $0.dmg }, 0)
        var offFlat = [Float](repeating: 0, count: nn * mc * 2)
        for g in 0..<nn { let o = scheds[g].offset; for i in 0..<o.count { offFlat[(g * mc + i) * 2] = o[i][0]; offFlat[(g * mc + i) * 2 + 1] = o[i][1] } }
        cOffset = MLXArray(offFlat, [nn, mc, 2])
        arenaHalf = scheds.map { $0.arena_half }
        cArena = MLXArray(arenaHalf, [nn])
        monType = scheds.map { sc in (0..<mc).map { $0 < sc.type.count ? sc.type[$0] : 0 } }
        monBox = scheds.map { sc in (0..<mc).map { $0 < sc.boxW.count ? sc.boxW[$0] : 1 } }

        pPos = MLXArray.zeros([nn, 2])
        pHP = MLXArray(Array(repeating: w.player_max_hp, count: nn), [nn])
        pAim = MLXArray(Array(repeating: Float(0), count: nn * 2), [nn, 2])
        mPos = MLXArray.zeros([nn, mc, 2]); mVel = MLXArray.zeros([nn, mc, 2])
        mHP = cHP0; mAct = MLXArray.zeros([nn, mc]); mContact = MLXArray.zeros([nn, mc])
        bPos = MLXArray.zeros([nn, bb, 2]); bVel = MLXArray.zeros([nn, bb, 2])
        bAlive = MLXArray.zeros([nn, bb]); bDist = MLXArray.zeros([nn, bb]); bPen = MLXArray.zeros([nn, bb])
        ammo = MLXArray(Array(repeating: Float(magSize), count: nn), [nn]); reloadT = MLXArray.zeros([nn])
        kills = MLXArray.zeros([nn])
    }

    // ---- parity replay (N=1): per-tick env-0 trajectory, same shape PortSim.runPort dumps ----
    func parityRun() -> [FrameOut] {
        var out: [FrameOut] = []
        for t in 1...ticks {
            step(t)
            let alive = which(logicalAnd(greater(mAct, 0.5), greater(mHP, 0)), MLXArray(1.0), MLXArray(0.0))
            eval(pPos, pHP, mPos, alive, bPos, bAlive, kills)
            let pp = pPos.asArray(Float.self), al = alive.asArray(Float.self)
            let k = Int(kills.asArray(Float.self)[0]), hp = pHP.asArray(Float.self)[0]
            out.append(FrameOut(t: t, player: [pp[0], pp[1]], mon_alive: al.map { $0 > 0.5 ? 1 : 0 },
                                mon_pos: mPos.asArray(Float.self), bul_alive: bAlive.asArray(Float.self).map { $0 > 0.5 ? 1 : 0 },
                                bul_pos: bPos.asArray(Float.self), kills: k, hp: hp))
            if hp <= 0 || k >= M { break }
        }
        return out
    }

    private func playerObs() -> MLXArray {                              // [N,8]
        let rel = mPos - pPos.expandedDimensions(axis: 1)              // [N,M,2]
        let dist = sqrt((rel * rel).sum(axis: 2)) + eps               // [N,M]
        let alive = which(logicalAnd(greater(mAct, 0.5), greater(mHP, 0)), MLXArray(1.0), MLXArray(0.0))
        let cnt = alive.sum(axis: 1)                                   // [N]
        let dirv = rel / dist.expandedDimensions(axis: 2)            // [N,M,2]
        let threat = (dirv * alive.expandedDimensions(axis: 2)).sum(axis: 1)  // [N,2]
        let threatN = threat / (sqrt((threat * threat).sum(axis: 1, keepDims: true)) + eps)
        let masked = which(greater(alive, 0.5), dist, MLXArray(1e9))
        let nearest = masked.min(axis: 1)                             // [N]
        let meanD = (dist * alive).sum(axis: 1) / (cnt + eps)
        let wall = pPos / cArena.expandedDimensions(axis: 1)        // [N,2]
        let c = { (a: MLXArray) in a.expandedDimensions(axis: 1) }   // [N] -> [N,1]
        return concatenated([
            c(pHP / w.player_max_hp), c(cnt / w.monster_count_norm), threatN,
            c(nearest / w.dist_norm), c(meanD / w.dist_norm), wall,
        ], axis: 1)                                                   // [N,8]
    }

    private func enemyObs() -> MLXArray {                             // [N,M,10]
        let rel = pPos.expandedDimensions(axis: 1) - mPos            // [N,M,2]
        let dist = sqrt((rel * rel).sum(axis: 2)) + eps              // [N,M]
        let dirv = rel / dist.expandedDimensions(axis: 2)
        let velN = mVel / (cSpeed.expandedDimensions(axis: 2) + eps)
        let brel = bPos.expandedDimensions(axis: 1) - mPos.expandedDimensions(axis: 2)  // [N,M,B,2]
        var bd2 = (brel * brel).sum(axis: 3)                          // [N,M,B]
        bd2 = which(greater(bAlive.expandedDimensions(axis: 1), 0.5), bd2, MLXArray(1e18))
        let bidx = bd2.argMin(axis: 2)                                // [N,M]
        let idxB = broadcast(bidx.expandedDimensions(axes: [2, 3]), to: [N, M, 1, 2])
        let bnear = takeAlong(brel, idxB, axis: 2).squeezed(axis: 2)  // [N,M,2]
        let bmin = bd2.min(axis: 2)                                   // [N,M]
        let has = which(less(bmin, 1e17), MLXArray(1.0), MLXArray(0.0))
        let bdist = sqrt(maximum(bmin, MLXArray(0.0))) + eps
        let bdir = bnear / bdist.expandedDimensions(axis: 2) * has.expandedDimensions(axis: 2)
        let bdistN = which(greater(has, 0.5), clip(bdist / w.bullet_norm, max: MLXArray(2.0)), MLXArray(2.0))
        let c = { (a: MLXArray) in a.expandedDimensions(axis: 2) }   // [N,M] -> [N,M,1]
        return concatenated([
            dirv, c(dist / w.dist_norm), velN, c(cSpeed / w.monster_speed_norm),
            c(mHP / (cHP0 + eps)), bdir, c(bdistN),
        ], axis: 2)                                                   // [N,M,10]
    }

    func step(_ t: Int) {
        let a = player(playerObs())                                   // [N,4]
        let dt = w.dt
        let elapsed = Float(t) * dt

        // spawn
        let due = lessEqual(cSpawn, elapsed)
        let just = logicalAnd(due, less(mAct, 0.5))
        mPos = which(just.expandedDimensions(axis: 2), pPos.expandedDimensions(axis: 1) + cOffset, mPos)
        mAct = maximum(mAct, which(just, MLXArray(1.0), MLXArray(0.0)))
        let aliveB = logicalAnd(due, greater(mHP, 0))

        // enemy net velocity + move
        let rel = pPos.expandedDimensions(axis: 1) - mPos
        let distPre = sqrt((rel * rel).sum(axis: 2)) + eps
        let stop = w.player_radius + cBoxW / 2
        let moveMask = which(logicalAnd(aliveB, greater(distPre, stop)), MLXArray(1.0), MLXArray(0.0))
        let v = tanh(enemy(enemyObs()))                               // [N,M,2]
        let vn = v / (sqrt((v * v).sum(axis: 2, keepDims: true)) + eps)
        mVel = vn * cSpeed.expandedDimensions(axis: 2) * moveMask.expandedDimensions(axis: 2)
        mPos = mPos + mVel * dt

        // ammo / reload + fire (per game)
        let aAim = a[0..., 2..<4]                                     // [N,2]
        let aim = aAim / (sqrt((aAim * aAim).sum(axis: 1, keepDims: true)) + eps)
        pAim = aim
        let reloadPrev = reloadT
        reloadT = maximum(reloadPrev - 1, MLXArray(0.0))
        let justReloaded = logicalAnd(greater(reloadPrev, 0), lessEqual(reloadT, 0))
        ammo = which(justReloaded, MLXArray(Float(magSize)), ammo)
        let gate = (t % fireInterval == 0)
        let fireF = gate
            ? which(logicalAnd(greater(ammo, 0), lessEqual(reloadT, 0)), MLXArray(1.0), MLXArray(0.0))
            : MLXArray.zeros([N])
        ammo = ammo - fireF
        let needReload = logicalAnd(lessEqual(ammo, 0), lessEqual(reloadT, 0))
        reloadT = which(needReload, MLXArray(Float(reloadTicks)), reloadT)

        // pellets (vectorized over K, shared across games) — det_rand int64 hash, one-hot ring slots
        let K = bulletsPerShot
        let shot = t / fireInterval
        let kIdx = MLXArray.arange(K, dtype: .int64)
        let hbase = Int(t) * 2654435761 + 12345
        let dr = ((kIdx * 340573 + hbase) % 4294967296).asType(.float32) / 2147483647.5 - 1.0  // [K]
        let theta = atan2(maxDev * dr, MLXArray(Float(500)))
        let ctA = cos(theta), stA = sin(theta)                        // [K]
        let slots = (kIdx + (shot * K)) % B
        let bIdx = MLXArray.arange(B, dtype: .int64)
        let oh = which(equal(slots.expandedDimensions(axis: 1), bIdx.expandedDimensions(axis: 0)),
                       MLXArray(1.0), MLXArray(0.0))                   // [K,B]
        let ax = aim[0..., 0..<1], ay = aim[0..., 1..<2]              // [N,1]
        let paX = ax * ctA.expandedDimensions(axis: 0) - ay * stA.expandedDimensions(axis: 0)  // [N,K]
        let paY = ax * stA.expandedDimensions(axis: 0) + ay * ctA.expandedDimensions(axis: 0)
        let velK = stacked([paX, paY], axis: 2) * bulletSpeed         // [N,K,2]
        let velB = einsum("kb,nkc->nbc", oh, velK)                    // [N,B,2]
        let writeB = clip(oh.sum(axis: 0), max: MLXArray(1.0)).expandedDimensions(axis: 0) * fireF.expandedDimensions(axis: 1)  // [N,B]
        let wcol = writeB.expandedDimensions(axis: 2)
        bPos = which(greater(wcol, 0.5), broadcast(pPos.expandedDimensions(axis: 1), to: [N, B, 2]), bPos)
        bVel = which(greater(wcol, 0.5), velB, bVel)
        bAlive = which(greater(writeB, 0.5), MLXArray(1.0), bAlive)
        bDist = which(greater(writeB, 0.5), MLXArray(0.0), bDist)
        bPen = which(greater(writeB, 0.5), MLXArray(Float(penetration)), bPen)

        // move bullets, expire
        bPos = bPos + bVel * dt
        bDist = bDist + sqrt((bVel * bVel).sum(axis: 2)) * dt
        bAlive = which(logicalAnd(greater(bAlive, 0.5), less(bDist, bulletRange)), MLXArray(1.0), MLXArray(0.0))

        // collision + penetration
        let diff = bPos.expandedDimensions(axis: 2) - mPos.expandedDimensions(axis: 1)  // [N,B,M,2]
        let d2 = (diff * diff).sum(axis: 3)                           // [N,B,M]
        let hitR = w.bullet_radius + cBoxW / 2                         // [N,M]
        let hitRsq = (hitR * hitR).expandedDimensions(axis: 1)       // [N,1,M]
        let hitMask = logicalAnd(logicalAnd(less(d2, hitRsq),
                                            greater(bAlive, 0.5).expandedDimensions(axis: 2)),
                                 aliveB.expandedDimensions(axis: 1))  // [N,B,M]
        let hitF = which(hitMask, MLXArray(1.0), MLXArray(0.0))
        mHP = mHP - (hitF * bulletDamage).sum(axis: 1)                // [N,M]
        bPen = bPen - hitF.sum(axis: 2)                               // [N,B]
        bAlive = which(logicalAnd(greater(bAlive, 0.5), greater(bPen, 0.5)), MLXArray(1.0), MLXArray(0.0))

        // kills (per game)
        let aliveA = logicalAnd(due, greater(mHP, 0))
        kills = kills + which(logicalAnd(aliveB, logicalNot(aliveA)), MLXArray(1.0), MLXArray(0.0)).sum(axis: 1)

        // contact damage
        let gateC: Float = (t % contactInterval == 0) ? 1 : 0
        let contactNow = which(logicalAnd(aliveA, less(distPre, w.player_radius + cBoxW / 2 + w.buffer)),
                               MLXArray(1.0), MLXArray(0.0))
        let newly = contactNow * (1 - mContact)
        let sustained = contactNow * mContact
        let dmg = ((newly + sustained * gateC) * cDmg).sum(axis: 1)   // [N]
        let applied = which(greater(dmg, 0), clip(dmg - defense, min: MLXArray(w.defense_min_floor)), MLXArray(0.0))
        pHP = pHP - applied
        mContact = contactNow

        // player move
        let mv = tanh(a[0..., 0..<2])                                 // [N,2]
        let lo = -cArena + w.player_half, hi = cArena - w.player_half // [N]
        pPos = clip(pPos + mv * (w.player_speed * exoSpeed * dt),
                    min: lo.expandedDimensions(axis: 1), max: hi.expandedDimensions(axis: 1))
    }

    /// play all N games to `ticks`, capture a script every `stride` frames + each game's freeze frame.
    func record(stride: Int) -> (frames: [GridFrame], endFrame: [Int]) {
        var frames: [GridFrame] = []
        var done = [Bool](repeating: false, count: N)
        var endF = [Int](repeating: -1, count: N)
        let aliveMask = { which(logicalAnd(greater(self.mAct, 0.5), greater(self.mHP, 0)), MLXArray(1.0), MLXArray(0.0)) }
        for t in 1...ticks {
            step(t)
            let alive = aliveMask()                                    // [N,M]
            if t == 1 || t % stride == 0 {
                eval(pPos, pHP, pAim, mPos, mVel, alive, bPos, bVel, bAlive)
                frames.append(GridFrame(
                    player: pPos.asArray(Float.self), playerAim: pAim.asArray(Float.self),
                    monPos: mPos.asArray(Float.self), monVel: mVel.asArray(Float.self),
                    monAlive: alive.asArray(Float.self),
                    bulPos: bPos.asArray(Float.self), bulVel: bVel.asArray(Float.self),
                    bulAlive: bAlive.asArray(Float.self),
                    kills: MLXArray.zeros([N]).asArray(Float.self), hp: pHP.asArray(Float.self)))
            }
            // per-game freeze: player dead, or every scheduled monster spawned-and-cleared, or timeout
            let hpA = pHP.asArray(Float.self)
            let aliveCount = alive.sum(axis: 1).asArray(Float.self)
            for g in 0..<N where !done[g] {
                let cleared = (aliveCount[g] < 0.5) && spawnedAll(g, t)
                if hpA[g] <= 0 || cleared || t >= ticks { done[g] = true; endF[g] = frames.count - 1 }
            }
            if done.allSatisfy({ $0 }) { break }
        }
        for g in 0..<N where endF[g] < 0 { endF[g] = frames.count - 1 }
        return (frames, endF)
    }

    // every monster scheduled to spawn has appeared by tick t (host check on spawn-tick seconds)
    private lazy var spawnSecs: [[Float]] = {
        let arr = cSpawn.asArray(Float.self)
        return (0..<N).map { g in (0..<M).map { arr[g * M + $0] } }
    }()
    private func spawnedAll(_ g: Int, _ t: Int) -> Bool {
        let elapsed = Float(t) * w.dt
        return spawnSecs[g].allSatisfy { $0 > 1e29 || $0 <= elapsed }
    }
}
