import Foundation
import Metal
import simd

// The playable game on Metal: it's the batched sim (GridSim) at N=1 — the SAME engine that plays the 3x3
// grid, just one env. The human moves player[0] (monsters net-driven), and the REAL game sprites are drawn
// via SpriteRenderer. Fixed 1/30 simulation with render interpolation (lerp prev→cur) for smooth 60/120 Hz.

private func lerp(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ t: Float) -> SIMD2<Float> { a + (b - a) * t }

final class Game {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let sprites: SpriteRenderer
    let sim: GridSim
    let simDt: Float
    let viewHalf: Float
    let modelDriven: Bool          // true = trained player model drives the player (demo); else human/scripted
    let typeRot: [Int: Float]      // per-type sprite facing offset (atlas orientation correction)
    var tick = 0
    var accum: Float = 0

    var prevPlayer = SIMD2<Float>(0, 0), curPlayer = SIMD2<Float>(0, 0)
    var prevMon: [SIMD2<Float>], curMon: [SIMD2<Float>]
    var prevBul: [SIMD2<Float>], curBul: [SIMD2<Float>]
    var prevAct: [Float], prevBulAlive: [Float]    // spawn detection (no lerp on the frame a thing appears)
    var monRot: [Float], bulRot: [Float], playerRot: Float = 0   // last facing (held when idle)

    var php: Float { sim.playerHP }
    var kills: UInt32 { UInt32(sim.killsInt) }
    var alive: Bool { sim.playerHP > 0 }

    init(mapPath: String = "../torchsim/datasets/tiny/eval/e3.json",
         clientRoot: String = "../monstro_client",
         enemyPath: String = "models/monster.json", playerPath: String = "",
         bullets: Int = 24, seed: UInt64 = 12345) throws {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else {
            throw NSError(domain: "game", code: 1, userInfo: [NSLocalizedDescriptionKey: "no Metal device"])
        }
        device = d; queue = q
        let world = defaultWorld()                              // canonical constants, built in
        guard let (sched, folders, rotOffsets) = generateSched(mapPath: mapPath, clientRoot: clientRoot,
                                                              bullets: bullets, seed: seed, dt: world.dt) else {
            throw NSError(domain: "game", code: 3, userInfo: [NSLocalizedDescriptionKey: "bad map/configs at \(mapPath)"])
        }
        typeRot = rotOffsets
        guard let enemy = MLXMLP(path: enemyPath) else {
            throw NSError(domain: "game", code: 2, userInfo: [NSLocalizedDescriptionKey: "no enemy model at \(enemyPath)"])
        }
        let modelPlayer = playerPath.isEmpty ? nil : MLXMLP(path: playerPath)
        modelDriven = modelPlayer != nil
        sim = GridSim(w: world, scheds: [sched], player: modelPlayer ?? enemy, enemy: enemy)  // N=1
        simDt = world.dt
        viewHalf = min(sched.arena_half, 700)
        let typesInUse = Array(Set(sched.type)).sorted()
        sprites = try SpriteRenderer(device: d, assetsRoot: "\(clientRoot)/Assets.xcassets",
                                     resourcesRoot: "\(clientRoot)/Resources", typeFolders: folders,
                                     playerImage: "exoskeletons_0.png", playerCrop: [1, 1, 62, 57],
                                     typesInUse: typesInUse, maxInstances: 1 + sched.M + sched.B)
        prevMon = Array(repeating: .zero, count: sched.M); curMon = prevMon
        prevBul = Array(repeating: .zero, count: sched.B); curBul = prevBul
        prevAct = Array(repeating: 0, count: sched.M); prevBulAlive = Array(repeating: 0, count: sched.B)
        monRot = Array(repeating: 0, count: sched.M); bulRot = Array(repeating: 0, count: sched.B)
        sim.materialize()
        snapshot()
    }

    private func snapshot() {
        curPlayer = sim.playerPos
        for m in 0..<sim.M { curMon[m] = sim.monPos(m) }
        for b in 0..<sim.B { curBul[b] = sim.bulPos(b) }
    }

    /// Advance real time; step the sim at the FIXED 1/30 rate (catch-up accumulator). 0.75 diagonal.
    func step(dt: Float, moveDir: SIMD2<Float>) {
        accum += dt
        var mv = moveDir
        if abs(mv.x) > 0.1 && abs(mv.y) > 0.1 { mv *= sim.w.diagonal_factor }
        while accum >= simDt {
            prevPlayer = curPlayer; prevMon = curMon; prevBul = curBul
            tick += 1
            if modelDriven { sim.step(tick) } else { sim.stepHuman(tick, move: mv, aim: sim.nearestVec()) }
            sim.materialize()
            snapshot()
            // facing (hold last when ~idle) + no-lerp on spawn frame
            playerRot = atan2f(sim.lastAim.y, sim.lastAim.x) - .pi / 2
            for m in 0..<sim.M {
                // face velocity + the type's atlas-orientation offset (from the YAML; 0 for these types,
                // NOT the GameConstants π/4 default — that's what made them face sideways)
                let v = sim.monVel(m)
                if simd_length(v) > 1 { monRot[m] = atan2f(v.y, v.x) + (typeRot[sim.monType[0][m]] ?? .pi / 4) }
                let now: Float = (sim.monAct[m] > 0.5 && sim.monHP[m] > 0) ? 1 : 0
                if now > 0.5 && prevAct[m] < 0.5 { prevMon[m] = curMon[m] }
                prevAct[m] = now
            }
            for b in 0..<sim.B {
                let v = sim.bulVel(b); if simd_length(v) > 1 { bulRot[b] = atan2f(v.y, v.x) }
                if sim.bulAlive[b] > 0.5 && prevBulAlive[b] < 0.5 { prevBul[b] = curBul[b] }
                prevBulAlive[b] = sim.bulAlive[b]
            }
            accum -= simDt
        }
    }

    private func instances(_ alpha: Float) -> [SpriteInstance] {
        let frame = tick / 3                                   // animation frame
        var out: [SpriteInstance] = []
        // monsters (real Walk sprite, animated, sized by hitbox)
        for m in 0..<sim.M where sim.monAct[m] > 0.5 && sim.monHP[m] > 0 {
            let pos = lerp(prevMon[m], curMon[m], alpha)
            out.append(SpriteInstance(pos: pos, rot: monRot[m], size: sim.monBox[0][m] * 0.8,
                                      slice: sprites.monsterSlice(sim.monType[0][m], frame), pad: 0))
        }
        // bullets (real weapons.png art, ~12px, facing travel)
        for b in 0..<sim.B where sim.bulAlive[b] > 0.5 {
            let pos = lerp(prevBul[b], curBul[b], alpha)
            out.append(SpriteInstance(pos: pos, rot: bulRot[b], size: 7, slice: sprites.bulletSlice, pad: 0))
        }
        // player on top (faces aim)
        out.append(SpriteInstance(pos: lerp(prevPlayer, curPlayer, alpha), rot: playerRot,
                                   size: sim.w.player_radius * 1.3, slice: sprites.playerSlice, pad: 0))
        return out
    }

    private func encode(_ rp: MTLRenderPassDescriptor) -> MTLCommandBuffer {
        let alpha = min(accum / simDt, 1)
        let center = lerp(prevPlayer, curPlayer, alpha)
        let cmd = queue.makeCommandBuffer()!
        sprites.encode(into: cmd, rp: rp, instances: instances(alpha),
                       camCenter: center, camHalf: SIMD2<Float>(viewHalf, viewHalf))
        return cmd
    }

    func render(into tex: MTLTexture) {
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = tex
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1)
        rp.colorAttachments[0].storeAction = .store
        let cmd = encode(rp); cmd.commit(); cmd.waitUntilCompleted()
    }

    func render(passDescriptor rp: MTLRenderPassDescriptor, drawable: MTLDrawable) {
        let cmd = encode(rp); cmd.present(drawable); cmd.commit()
    }
}
