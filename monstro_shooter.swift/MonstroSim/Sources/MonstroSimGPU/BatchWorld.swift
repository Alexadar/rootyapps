import Foundation
import MLX
import MonstroSim

// Vectorized, GPU-resident batch of N MonstroSim environments (Brax/Isaac-Gym style).
// Structure-of-arrays tensors with a leading [N] env dim; all dynamics are branchless
// (`where` + masks), fixed-size buffers (pad + alive-mask), no host syncs per step.
//
// v1 scope (throughput benchmark + rule-parity anchor): masked spawn activation from the
// CPU-precomputed schedule, monster steering (direct & arc), reduction-based bullet↔monster
// collisions, periodic contact damage, scripted kite+auto-fire policy. The weapon model is a
// fixed-cadence auto-fire toward the monster centroid (scatter-free); the exact per-env weapon
// state machine and the every-4th-hit damage floor are parity-phase refinements (defense=0 here,
// so contact damage matches exactly).
public final class BatchWorld {
    public let n: Int                 // envs
    public let m: Int                 // monster slots
    public let b: Int                 // bullet slots
    public private(set) var t = 0     // tick

    // Constants (mirror SimConstants).
    private let dt = Float(SimConstants.tickDelta)
    private let playerRadius = Float(SimConstants.playerHitboxRadius)
    private let playerSpeed = Float(SimConstants.playerSpeed)
    private let mapHalf = Float(SimConstants.mapSize / 2)
    private let playerHalf = Float(SimConstants.playerSize / 2)
    private let buffer = Float(SimConstants.contactBuffer)
    private let bulletRadius = Float(SimConstants.bulletRadius)
    private let turnRate: Float = 34
    private let eps: Float = 1e-6

    // Weapon (from config; v1 fixed per BatchWorld).
    private let bulletSpeed: Float
    private let bulletDamage: Float
    private let bulletRange: Float
    private let fireInterval: Int   // ticks between auto-fires
    private let contactInterval: Int
    private let playerDefense: Float

    // Precomputed schedule (constants).
    private let spawnTick, offset, monSpeed, monBoxW, monDamage, monDirect, hp0: MLXArray

    // Mutable state.
    private var playerPos, playerHP: MLXArray
    private var monPos, monVel, monHP, monActivated: MLXArray
    private var bulPos, bulVel, bulAlive, bulDist: MLXArray
    public private(set) var killCount: MLXArray

    public init(schedule s: SpawnSchedule, weapon: WeaponCfg, exo: ExoCfg) {
        self.n = s.nEnvs
        self.m = s.maxMon
        self.b = 128
        self.bulletSpeed = Float(weapon.bulletSpeed)
        self.bulletDamage = Float(weapon.damage)
        self.bulletRange = Float(weapon.shotRange)
        self.fireInterval = max(1, Int((weapon.shotDelay / SimConstants.tickDelta).rounded()))
        self.contactInterval = max(1, Int(SimConstants.damageInterval / SimConstants.tickDelta))
        self.playerDefense = Float(exo.defence)

        spawnTick = MLXArray(s.spawnTick, [n, m])
        offset = MLXArray(s.offsetX.enumerated().flatMap { [$0.element, s.offsetY[$0.offset]] }, [n, m, 2])
        monSpeed = MLXArray(s.speed, [n, m])
        monBoxW = MLXArray(s.boxW, [n, m])
        monDamage = MLXArray(s.damage, [n, m])
        monDirect = MLXArray(s.direct, [n, m])
        hp0 = MLXArray(s.hp0, [n, m])

        playerPos = MLXArray.zeros([n, 2])
        playerHP = MLXArray(Array(repeating: Float(SimConstants.playerMaxHealth), count: n), [n])
        monPos = MLXArray.zeros([n, m, 2])
        monVel = MLXArray.zeros([n, m, 2])
        monHP = hp0
        monActivated = MLXArray.zeros([n, m])
        bulPos = MLXArray.zeros([n, b, 2])
        bulVel = MLXArray.zeros([n, b, 2])
        bulAlive = MLXArray.zeros([n, b])
        bulDist = MLXArray.zeros([n, b])
        killCount = MLXArray.zeros([n])
        eval(spawnTick, offset, monSpeed, monBoxW, monDamage, monDirect, hp0, playerHP)
    }

    // MARK: - Fused step (mx.compile)
    // The whole step as one pure function (state + per-tick gates) -> state, compiled once so MLX
    // fuses the ~70 small kernels into a handful. Fire/contact are gated by 0/1 scalars (not Swift
    // branches) so the traced graph is identical every tick. Constants are captured.
    private lazy var compiled: ([MLXArray]) -> [MLXArray] = MLX.compile(shapeless: false) { io in
        let dt = self.dt, eps = self.eps
        var playerPos = io[0]; var playerHP = io[1]
        var monPos = io[2]; var monVel = io[3]; var monHP = io[4]; var monActivated = io[5]
        var bulPos = io[6]; var bulVel = io[7]; var bulAlive = io[8]; var bulDist = io[9]
        var killCount = io[10]
        let elapsed = io[11], fireGate = io[12], slotB1 = io[13], slotB = io[14], contactGate = io[15]

        // spawn activation
        let due = self.spawnTick .<= elapsed
        let justAct = MLX.logicalAnd(due, monActivated .< 0.5)
        monPos = MLX.where(justAct.expandedDimensions(axis: 2), playerPos.expandedDimensions(axis: 1) + self.offset, monPos)
        monActivated = MLX.maximum(monActivated, justAct.asType(.float32))
        let aliveBefore = MLX.logicalAnd(due, monHP .> 0)

        // steering (mask-multiply instead of where+zeros; both branches computed then selected)
        let rel = playerPos.expandedDimensions(axis: 1) - monPos
        let dist = MLX.sqrt((rel * rel).sum(axis: 2)) + eps
        let dir = rel / dist.expandedDimensions(axis: 2)
        let stop = self.playerRadius + self.monBoxW / 2
        let moveMask = MLX.logicalAnd(aliveBefore, dist .> stop).asType(.float32)
        let directVel = dir * self.monSpeed.expandedDimensions(axis: 2)
        let arcAccum = monVel + dir * (self.turnRate * dt)
        let arcSpeed = MLX.sqrt((arcAccum * arcAccum).sum(axis: 2)) + eps
        let arcVel = arcAccum / arcSpeed.expandedDimensions(axis: 2) * self.monSpeed.expandedDimensions(axis: 2)
        let chosen = MLX.where((self.monDirect .> 0.5).expandedDimensions(axis: 2), directVel, arcVel)
        monVel = chosen * moveMask.expandedDimensions(axis: 2)
        monPos = monPos + monVel * dt

        // auto-fire toward centroid, gated by fireGate (no Swift branch)
        let toMon = monPos - playerPos.expandedDimensions(axis: 1)
        let sumDir = (toMon * aliveBefore.asType(.float32).expandedDimensions(axis: 2)).sum(axis: 1)
        let aim = sumDir / (MLX.sqrt((sumDir * sumDir).sum(axis: 1, keepDims: true)) + eps)
        let writeB1 = slotB1 * fireGate           // [1,B,1] active only on fire ticks
        let writeB = slotB * fireGate
        bulPos = MLX.where(writeB1 .> 0.5, playerPos.expandedDimensions(axis: 1), bulPos)
        bulVel = MLX.where(writeB1 .> 0.5, (aim * self.bulletSpeed).expandedDimensions(axis: 1), bulVel)
        bulAlive = MLX.where(writeB .> 0.5, MLXArray(Float(1)), bulAlive)
        bulDist = MLX.where(writeB .> 0.5, MLXArray(Float(0)), bulDist)

        // bullets move + expire
        bulPos = bulPos + bulVel * dt
        bulDist = bulDist + MLX.sqrt((bulVel * bulVel).sum(axis: 2)) * dt
        bulAlive = MLX.logicalAnd(bulAlive .> 0.5, bulDist .< self.bulletRange).asType(.float32)

        // collision (fused reduction)
        let diff = bulPos.expandedDimensions(axis: 2) - monPos.expandedDimensions(axis: 1)
        let d2 = (diff * diff).sum(axis: 3)
        let hitR = self.bulletRadius + self.monBoxW / 2
        let hit = MLX.logicalAnd(d2 .< (hitR * hitR).expandedDimensions(axis: 1),
                                 MLX.logicalAnd((bulAlive .> 0.5).expandedDimensions(axis: 2),
                                                aliveBefore.expandedDimensions(axis: 1))).asType(.float32)
        monHP = monHP - (hit * self.bulletDamage).sum(axis: 1)
        bulAlive = MLX.logicalAnd(bulAlive .> 0.5, hit.sum(axis: 2) .< 0.5).asType(.float32)

        // kills
        let aliveAfter = MLX.logicalAnd(due, monHP .> 0)
        killCount = killCount + MLX.logicalAnd(aliveBefore, aliveAfter .< 0.5).asType(.float32).sum(axis: 1)

        // contact damage, gated
        let contact = MLX.logicalAnd(aliveAfter, dist .< (self.playerRadius + self.monBoxW / 2 + self.buffer)).asType(.float32)
        let dmg = (contact * self.monDamage).sum(axis: 1) * contactGate
        playerHP = playerHP - MLX.maximum(dmg - self.playerDefense, MLXArray(Float(0)))

        // player kite
        let centroid = (toMon * aliveAfter.asType(.float32).expandedDimensions(axis: 2)).sum(axis: 1)
        let awayN = (centroid * MLXArray(Float(-1))) / (MLX.sqrt((centroid * centroid).sum(axis: 1, keepDims: true)) + eps)
        playerPos = MLX.clip(playerPos + awayN * (self.playerSpeed * dt),
                             min: MLXArray(-self.mapHalf + self.playerHalf), max: MLXArray(self.mapHalf - self.playerHalf))

        return [playerPos, playerHP, monPos, monVel, monHP, monActivated, bulPos, bulVel, bulAlive, bulDist, killCount]
    }

    /// Fused step: builds per-tick gate scalars, runs the compiled graph, one eval.
    public func stepFused() {
        t += 1
        let fire = t % fireInterval == 0
        let contact = t % contactInterval == 0
        let slot = fire ? (t / fireInterval) % b : 0
        var oh = [Float](repeating: 0, count: b); if fire { oh[slot] = 1 }
        let io: [MLXArray] = [
            playerPos, playerHP, monPos, monVel, monHP, monActivated, bulPos, bulVel, bulAlive, bulDist, killCount,
            MLXArray(Float(t) * dt), MLXArray(Float(fire ? 1 : 0)),
            MLXArray(oh, [1, b, 1]), MLXArray(oh, [1, b]), MLXArray(Float(contact ? 1 : 0)),
        ]
        let o = compiled(io)
        playerPos = o[0]; playerHP = o[1]; monPos = o[2]; monVel = o[3]; monHP = o[4]; monActivated = o[5]
        bulPos = o[6]; bulVel = o[7]; bulAlive = o[8]; bulDist = o[9]; killCount = o[10]
        eval(o)
    }

    // MARK: - On-device player policy (Phase A)

    /// Reset mutable state for a fresh episode (constants/schedule untouched).
    public func resetState() {
        t = 0
        playerPos = MLXArray.zeros([n, 2])
        playerHP = MLXArray(Array(repeating: Float(SimConstants.playerMaxHealth), count: n), [n])
        monPos = MLXArray.zeros([n, m, 2]); monVel = MLXArray.zeros([n, m, 2])
        monHP = hp0; monActivated = MLXArray.zeros([n, m])
        bulPos = MLXArray.zeros([n, b, 2]); bulVel = MLXArray.zeros([n, b, 2])
        bulAlive = MLXArray.zeros([n, b]); bulDist = MLXArray.zeros([n, b])
        killCount = MLXArray.zeros([n])
    }

    /// Egocentric player observation built from GPU state (all tensor ops, no gather/sort).
    public func buildPlayerObs() -> MLXArray {
        let rel = monPos - playerPos.expandedDimensions(axis: 1)          // [N,M,2] toward monster
        let dist = MLX.sqrt((rel * rel).sum(axis: 2)) + eps               // [N,M]
        let alive = MLX.logicalAnd(monActivated .> 0.5, monHP .> 0).asType(.float32)
        let aliveCount = alive.sum(axis: 1)                               // [N]
        let dir = rel / dist.expandedDimensions(axis: 2)
        let threat = (dir * alive.expandedDimensions(axis: 2)).sum(axis: 1)  // [N,2] toward danger
        let threatN = threat / (MLX.sqrt((threat * threat).sum(axis: 1, keepDims: true)) + eps)
        let maskedDist = MLX.where(alive .> 0.5, dist, MLXArray(Float(1e9)))
        let nearest = maskedDist.min(axis: 1)                            // [N]
        let meanDist = (dist * alive).sum(axis: 1) / (aliveCount + eps)
        let health = playerHP / Float(SimConstants.playerMaxHealth)
        return MLX.concatenated([
            health.expandedDimensions(axis: 1),
            (aliveCount / Float(m)).expandedDimensions(axis: 1),
            threatN,
            (nearest / 1000).expandedDimensions(axis: 1),
            (meanDist / 1000).expandedDimensions(axis: 1),
        ], axis: 1)                                                       // [N,6]
    }

    /// Compiled step driven by the player's action (aMove,aAim) instead of the scripted kite,
    /// returning per-tick reward as the 12th output. Player controls move + aim; weapon auto-fires
    /// along aim at cadence (ammo not modeled in v1).
    private lazy var playerStep: ([MLXArray]) -> [MLXArray] = MLX.compile(shapeless: false) { io in
        let dt = self.dt, eps = self.eps
        var playerPos = io[0]; var playerHP = io[1]
        var monPos = io[2]; var monVel = io[3]; var monHP = io[4]; var monActivated = io[5]
        var bulPos = io[6]; var bulVel = io[7]; var bulAlive = io[8]; var bulDist = io[9]
        var killCount = io[10]
        let elapsed = io[11], fireGate = io[12], slotB1 = io[13], slotB = io[14], contactGate = io[15]
        let aMove = io[16], aAim = io[17]   // [N,2] each

        // spawn
        let due = self.spawnTick .<= elapsed
        let justAct = MLX.logicalAnd(due, monActivated .< 0.5)
        monPos = MLX.where(justAct.expandedDimensions(axis: 2), playerPos.expandedDimensions(axis: 1) + self.offset, monPos)
        monActivated = MLX.maximum(monActivated, justAct.asType(.float32))
        let aliveBefore = MLX.logicalAnd(due, monHP .> 0)

        // steering (scripted monsters in Phase A)
        let rel = playerPos.expandedDimensions(axis: 1) - monPos
        let dist = MLX.sqrt((rel * rel).sum(axis: 2)) + eps
        let dir = rel / dist.expandedDimensions(axis: 2)
        let stop = self.playerRadius + self.monBoxW / 2
        let moveMask = MLX.logicalAnd(aliveBefore, dist .> stop).asType(.float32)
        let directVel = dir * self.monSpeed.expandedDimensions(axis: 2)
        let arcAccum = monVel + dir * (self.turnRate * dt)
        let arcSpeed = MLX.sqrt((arcAccum * arcAccum).sum(axis: 2)) + eps
        let arcVel = arcAccum / arcSpeed.expandedDimensions(axis: 2) * self.monSpeed.expandedDimensions(axis: 2)
        let chosen = MLX.where((self.monDirect .> 0.5).expandedDimensions(axis: 2), directVel, arcVel)
        monVel = chosen * moveMask.expandedDimensions(axis: 2)
        monPos = monPos + monVel * dt

        // auto-fire along player's aim, gated
        let aim = aAim / (MLX.sqrt((aAim * aAim).sum(axis: 1, keepDims: true)) + eps)
        let writeB1 = slotB1 * fireGate
        let writeB = slotB * fireGate
        bulPos = MLX.where(writeB1 .> 0.5, playerPos.expandedDimensions(axis: 1), bulPos)
        bulVel = MLX.where(writeB1 .> 0.5, (aim * self.bulletSpeed).expandedDimensions(axis: 1), bulVel)
        bulAlive = MLX.where(writeB .> 0.5, MLXArray(Float(1)), bulAlive)
        bulDist = MLX.where(writeB .> 0.5, MLXArray(Float(0)), bulDist)

        // bullets move + expire
        bulPos = bulPos + bulVel * dt
        bulDist = bulDist + MLX.sqrt((bulVel * bulVel).sum(axis: 2)) * dt
        bulAlive = MLX.logicalAnd(bulAlive .> 0.5, bulDist .< self.bulletRange).asType(.float32)

        // collision
        let diff = bulPos.expandedDimensions(axis: 2) - monPos.expandedDimensions(axis: 1)
        let d2 = (diff * diff).sum(axis: 3)
        let hitR = self.bulletRadius + self.monBoxW / 2
        let hit = MLX.logicalAnd(d2 .< (hitR * hitR).expandedDimensions(axis: 1),
                                 MLX.logicalAnd((bulAlive .> 0.5).expandedDimensions(axis: 2),
                                                aliveBefore.expandedDimensions(axis: 1))).asType(.float32)
        monHP = monHP - (hit * self.bulletDamage).sum(axis: 1)
        bulAlive = MLX.logicalAnd(bulAlive .> 0.5, hit.sum(axis: 2) .< 0.5).asType(.float32)

        // kills
        let aliveAfter = MLX.logicalAnd(due, monHP .> 0)
        let killed = MLX.logicalAnd(aliveBefore, aliveAfter .< 0.5).asType(.float32).sum(axis: 1)  // [N]
        killCount = killCount + killed

        // contact damage, gated
        let contact = MLX.logicalAnd(aliveAfter, dist .< (self.playerRadius + self.monBoxW / 2 + self.buffer)).asType(.float32)
        let dmgRaw = (contact * self.monDamage).sum(axis: 1) * contactGate
        let applied = MLX.maximum(dmgRaw - self.playerDefense, MLXArray(Float(0)))            // [N]
        playerHP = playerHP - applied

        // player move from policy (tanh-bounded direction+magnitude)
        let mv = MLX.tanh(aMove)
        playerPos = MLX.clip(playerPos + mv * (self.playerSpeed * dt),
                             min: MLXArray(-self.mapHalf + self.playerHalf), max: MLXArray(self.mapHalf - self.playerHalf))

        // per-tick reward: survive + DENSE aim-shaping + kills - damage; alive-gated.
        // Aim-shaping (dot of aim with the monster-centroid direction) breaks the sparse-reward
        // flat landscape so ES has a gradient to learn aiming before any kill happens.
        let threatRaw = ((monPos - playerPos.expandedDimensions(axis: 1)) * aliveAfter.asType(.float32).expandedDimensions(axis: 2)).sum(axis: 1)
        let threatN = threatRaw / (MLX.sqrt((threatRaw * threatRaw).sum(axis: 1, keepDims: true)) + eps)
        let aimAlign = (aim * threatN).sum(axis: 1)   // [N] in [-1,1]
        let aliveEnv = (playerHP .> 0).asType(.float32)
        let reward = (MLXArray(Float(0.01)) + 0.005 * aimAlign + killed - applied * 0.05) * aliveEnv

        return [playerPos, playerHP, monPos, monVel, monHP, monActivated, bulPos, bulVel, bulAlive, bulDist, killCount, reward]
    }

    public struct RolloutResult {
        public let reward: [Float]
        public let kills: [Float]
        public let alive: [Float]   // 1 if survived to the end, else 0
        public var meanReward: Float { reward.isEmpty ? 0 : reward.reduce(0, +) / Float(reward.count) }
        public var meanKills: Float { kills.isEmpty ? 0 : kills.reduce(0, +) / Float(kills.count) }
        public var surviveRate: Float { alive.isEmpty ? 0 : alive.reduce(0, +) / Float(alive.count) }
    }

    /// Run a full episode driven by `net`, accumulating reward on-device. ONE sync at the end.
    public func rolloutPlayerFull(net: GPUPolicy, ticks: Int) -> RolloutResult {
        resetState()
        var rewardAcc = MLXArray.zeros([n])
        for tick in 1...ticks {
            t = tick
            let out = net(buildPlayerObs())                 // [N,4]
            let parts = MLX.split(out, parts: 2, axis: 1)   // move[N,2], aim[N,2]
            let fire = t % fireInterval == 0
            let contact = t % contactInterval == 0
            let slot = fire ? (t / fireInterval) % b : 0
            var oh = [Float](repeating: 0, count: b); if fire { oh[slot] = 1 }
            let o = playerStep([
                playerPos, playerHP, monPos, monVel, monHP, monActivated, bulPos, bulVel, bulAlive, bulDist, killCount,
                MLXArray(Float(t) * dt), MLXArray(Float(fire ? 1 : 0)),
                MLXArray(oh, [1, b, 1]), MLXArray(oh, [1, b]), MLXArray(Float(contact ? 1 : 0)),
                parts[0], parts[1],
            ])
            playerPos = o[0]; playerHP = o[1]; monPos = o[2]; monVel = o[3]; monHP = o[4]; monActivated = o[5]
            bulPos = o[6]; bulVel = o[7]; bulAlive = o[8]; bulDist = o[9]; killCount = o[10]
            rewardAcc = rewardAcc + o[11]
            // keep the pending graph bounded without a host sync
            if tick % 64 == 0 { eval(playerPos, playerHP, monPos, monHP, bulPos, bulAlive, killCount, rewardAcc) }
        }
        let alive = (playerHP .> 0).asType(.float32)
        eval(rewardAcc, killCount, alive)
        return RolloutResult(reward: rewardAcc.asArray(Float.self), kills: killCount.asArray(Float.self), alive: alive.asArray(Float.self))
    }

    /// Convenience: just the per-env reward (used by the ES fitness).
    public func rolloutPlayer(net: GPUPolicy, ticks: Int) -> [Float] {
        rolloutPlayerFull(net: net, ticks: ticks).reward
    }

    /// Read back per-env metrics (host sync — call only when needed, not in the hot loop).
    public func readback() -> (playerHP: [Float], kills: [Float]) {
        eval(playerHP, killCount)
        return (playerHP.asArray(Float.self), killCount.asArray(Float.self))
    }

    /// Force every monster slot active at the player+offset (worst-case "bullet-hell" density)
    /// for profiling/benchmarking the fully-loaded step.
    public func forceDenseActivation() {
        monActivated = MLXArray.ones([n, m])
        monPos = playerPos.expandedDimensions(axis: 1) + offset
        monHP = hp0
        // saturate bullets too
        bulAlive = MLXArray.ones([n, b])
        eval(monActivated, monPos, monHP, bulAlive)
    }

    /// One step instrumented per phase (eval barrier attributes GPU time). Returns (label, seconds).
    public func profileStep() -> [(String, Double)] {
        t += 1
        let elapsed = MLXArray(Float(t) * dt)
        var out: [(String, Double)] = []
        func phase(_ label: String, _ arrays: MLXArray..., body: () -> Void) {
            let t0 = DispatchTime.now()
            body()
            eval(arrays)
            out.append((label, Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9))
        }

        let due = spawnTick .<= elapsed
        let aliveBefore = MLX.logicalAnd(due, monHP .> 0)
        var rel = MLXArray.zeros([n, m, 2]); var dist = MLXArray.zeros([n, m])

        phase("spawn", monPos, monActivated) {
            let justAct = MLX.logicalAnd(due, monActivated .< 0.5)
            monPos = MLX.where(justAct.expandedDimensions(axis: 2), playerPos.expandedDimensions(axis: 1) + offset, monPos)
            monActivated = MLX.maximum(monActivated, justAct.asType(.float32))
        }
        phase("steering", monPos, monVel) {
            rel = playerPos.expandedDimensions(axis: 1) - monPos
            dist = MLX.sqrt((rel * rel).sum(axis: 2)) + eps
            let dir = rel / dist.expandedDimensions(axis: 2)
            let stop = playerRadius + monBoxW / 2
            let moveMask = MLX.logicalAnd(aliveBefore, dist .> stop)
            let directVel = dir * monSpeed.expandedDimensions(axis: 2)
            let arcAccum = monVel + dir * (turnRate * dt)
            let arcSpeed = MLX.sqrt((arcAccum * arcAccum).sum(axis: 2)) + eps
            let arcVel = arcAccum / arcSpeed.expandedDimensions(axis: 2) * monSpeed.expandedDimensions(axis: 2)
            let chosen = MLX.where((monDirect .> 0.5).expandedDimensions(axis: 2), directVel, arcVel)
            monVel = MLX.where(moveMask.expandedDimensions(axis: 2), chosen, MLXArray.zeros([n, m, 2]))
            monPos = monPos + monVel * dt
        }
        phase("bullets-move", bulPos, bulDist, bulAlive) {
            bulPos = bulPos + bulVel * dt
            bulDist = bulDist + MLX.sqrt((bulVel * bulVel).sum(axis: 2)) * dt
            bulAlive = MLX.logicalAnd(bulAlive .> 0.5, bulDist .< bulletRange).asType(.float32)
        }
        var hit = MLXArray.zeros([n, b, m])
        phase("collision [N,B,M]", monHP) {
            let diff = bulPos.expandedDimensions(axis: 2) - monPos.expandedDimensions(axis: 1)
            let d2 = (diff * diff).sum(axis: 3)
            let hitR2 = ((bulletRadius + monBoxW / 2) * (bulletRadius + monBoxW / 2)).expandedDimensions(axis: 1)
            let bulA = (bulAlive .> 0.5).expandedDimensions(axis: 2)
            let monA = aliveBefore.expandedDimensions(axis: 1)
            hit = MLX.logicalAnd(d2 .< hitR2, MLX.logicalAnd(bulA, monA)).asType(.float32)
            monHP = monHP - (hit * bulletDamage).sum(axis: 1)
        }
        phase("bullet-consume", bulAlive) {
            bulAlive = MLX.logicalAnd(bulAlive .> 0.5, hit.sum(axis: 2) .< 0.5).asType(.float32)
        }
        phase("contact+player", playerHP, playerPos, killCount) {
            let aliveAfter = MLX.logicalAnd(due, monHP .> 0)
            killCount = killCount + MLX.logicalAnd(aliveBefore, aliveAfter .< 0.5).asType(.float32).sum(axis: 1)
            let contact = MLX.logicalAnd(aliveAfter, dist .< (playerRadius + monBoxW / 2 + buffer)).asType(.float32)
            playerHP = playerHP - MLX.maximum((contact * monDamage).sum(axis: 1) - playerDefense, MLXArray(Float(0)))
            let centroidDir = ((monPos - playerPos.expandedDimensions(axis: 1)) * aliveAfter.asType(.float32).expandedDimensions(axis: 2)).sum(axis: 1)
            let awayN = (centroidDir * MLXArray(Float(-1))) / (MLX.sqrt((centroidDir * centroidDir).sum(axis: 1, keepDims: true)) + eps)
            playerPos = MLX.clip(playerPos + awayN * (playerSpeed * dt), min: MLXArray(-mapHalf + playerHalf), max: MLXArray(mapHalf - playerHalf))
        }
        return out
    }
}
