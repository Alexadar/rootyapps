import Foundation
import MonstroSim

// CPU-precomputed, deterministic spawn schedule — the rule-parity anchor for the GPU sim.
// For each env (own seed) and each monster slot we precompute: spawn tick, type, spawn OFFSET
// (side + jitter, exactly like CPU `spawnMonster`, minus the runtime player position), and the
// per-type stats. The GPU then just *applies* these (masked slot activation), so spawn timing,
// counts, types and stats match the CPU sim's rules.
//
// Layout: all arrays are row-major [N * M] (env-major), ready to upload as MLX [N, M] tensors.
public struct SpawnSchedule {
    public let nEnvs: Int
    public let maxMon: Int            // = min(level.expectedTotal, cap)

    public var spawnTick: [Float]     // [N*M] tick index when slot activates (dt steps)
    public var offsetX: [Float]       // [N*M] spawn offset relative to player at activation
    public var offsetY: [Float]
    public var hp0: [Float]           // [N*M] initial health (by type)
    public var speed: [Float]         // [N*M]
    public var boxW: [Float]          // [N*M]
    public var damage: [Float]        // [N*M]
    public var direct: [Float]        // [N*M] 1 = direct steering, 0 = arc

    public init(level: SimLevel, data: GameData, baseSeed: UInt64, nEnvs: Int, cap: Int = 512) {
        let total = min(level.expectedTotal, cap)
        self.nEnvs = nEnvs
        self.maxMon = max(total, 1)
        let count = nEnvs * maxMon
        spawnTick = [Float](repeating: .greatestFiniteMagnitude, count: count)
        offsetX = [Float](repeating: 0, count: count)
        offsetY = [Float](repeating: 0, count: count)
        hp0 = [Float](repeating: 1, count: count)
        speed = [Float](repeating: 0, count: count)
        boxW = [Float](repeating: 1, count: count)
        damage = [Float](repeating: 0, count: count)
        direct = [Float](repeating: 1, count: count)

        let hw = SimConstants.spawnHalfWidth, hh = SimConstants.spawnHalfHeight
        let dt = SimConstants.tickDelta

        for e in 0..<nEnvs {
            var rng = SeededGenerator(seed: baseSeed &+ UInt64(e))
            var slot = 0
            // Mirror processWaves + popSpawns scheduling: each wave enqueues `count` spawns
            // staggered by spawnInterval starting at the wave's startTime.
            for wave in level.waves {
                for k in 0..<wave.count {
                    if slot >= maxMon { break }
                    let tSeconds = wave.startTime + Double(k) * SimConstants.spawnInterval
                    let typeID = wave.typeIDs.randomElement(using: &rng) ?? wave.typeIDs[0]
                    // Random spawn side + jitter — same draws/branches as CPU spawnMonster (offset only).
                    let side = Int.random(in: 0...3, using: &rng)
                    var ox = 0.0, oy = 0.0
                    switch side {
                    case 0: ox = Double.random(in: -hw...hw, using: &rng); oy = hh
                    case 1: ox = hw; oy = Double.random(in: -hh...hh, using: &rng)
                    case 2: ox = Double.random(in: -hw...hw, using: &rng); oy = -hh
                    default: ox = -hw; oy = Double.random(in: -hh...hh, using: &rng)
                    }
                    let idx = e * maxMon + slot
                    // stored in SECONDS to match `elapsed = t*dt` in the GPU step (NOT tick units)
                    spawnTick[idx] = Float(tSeconds)
                    offsetX[idx] = Float(ox)
                    offsetY[idx] = Float(oy)
                    if let cfg = data.monsters[typeID] {
                        hp0[idx] = Float(cfg.health)
                        speed[idx] = Float(cfg.speed)
                        boxW[idx] = Float(cfg.boxWidth)
                        damage[idx] = Float(cfg.damage)
                        direct[idx] = cfg.useDirectSteering ? 1 : 0
                    }
                    slot += 1
                }
            }
        }
    }
}
