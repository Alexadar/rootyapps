import Foundation
import Metal
import simd

// The 3x3 (maps x seeds) grid, the way the user described it: the whole grid is played as ONE batched
// MLX rollout (GridSim, all games in parallel on the GPU), which records a replay "script"; then the real
// Swift Metal sprite renderer just plays that script back — every game laid out in its own cell of one big
// instance buffer, drawn in a single pass. Sim and render are fully decoupled (record once, draw N frames).
func runGrid() {
    func arg(_ k: String, _ d: Int) -> Int {
        CommandLine.arguments.firstIndex(of: "--\(k)").flatMap { Int(CommandLine.arguments[$0 + 1]) } ?? d
    }
    func argS(_ k: String, _ d: String) -> String {
        CommandLine.arguments.firstIndex(of: "--\(k)").map { CommandLine.arguments[$0 + 1] } ?? d
    }

    let clientRoot = argS("client", "../monstro_client")
    let evalDir = argS("eval", "../torchsim/datasets/tiny/eval")
    let mapNames = ["e1.json", "e2.json", "e3.json"]
    let maps = mapNames.map { "\(evalDir)/\($0)" }
    let seeds = arg("seeds", 3), bullets = arg("bullets", 24), stride = arg("stride", 2), panel = arg("panel", 300)
    let dir = argS("out", "/tmp/grid")
    let world = defaultWorld()

    // build N = maps x seeds schedules (same per-(map,seed) seeding as the parity/eval games)
    var scheds: [SchedJSON] = []
    var folders: [Int: String] = [:], rotOffsets: [Int: Float] = [:]
    for m in maps {
        for sd in 0 ..< seeds {
            guard let (sc, fol, rot) = generateSched(mapPath: m, clientRoot: clientRoot, bullets: bullets,
                                                     seed: UInt64(1000 + sd * 7919), dt: world.dt) else {
                FileHandle.standardError.write("grid: bad map \(m)\n".data(using: .utf8)!); exit(1)
            }
            scheds.append(sc)
            folders.merge(fol) { a, _ in a }; rotOffsets.merge(rot) { a, _ in a }
        }
    }
    guard let player = MLXMLP(path: argS("player", "models/player.json")),
          let enemy = MLXMLP(path: argS("enemy", "models/monster.json")) else {
        FileHandle.standardError.write("grid: no models\n".data(using: .utf8)!); exit(1)
    }
    let sim = GridSim(w: world, scheds: scheds, player: player, enemy: enemy)
    print("grid: \(sim.N) games (\(maps.count) maps x \(seeds) seeds), M=\(sim.M) B=\(sim.B) — one batched MLX rollout…")
    let (frames, endF) = sim.record(stride: stride)
    print("grid: recorded \(frames.count)-frame script")

    guard let device = MTLCreateSystemDefaultDevice() else { exit(1) }
    let typesInUse = Array(Set(scheds.flatMap { $0.type })).sorted()
    let sprites = try! SpriteRenderer(device: device, assetsRoot: "\(clientRoot)/Assets.xcassets",
                                      resourcesRoot: "\(clientRoot)/Resources", typeFolders: folders,
                                      playerImage: "exoskeletons_0.png", playerCrop: [1, 1, 62, 57],
                                      typesInUse: typesInUse, maxInstances: sim.N * (sim.M + sim.B + 1))
    let queue = device.makeCommandQueue()!

    let N = sim.N, M = sim.M, B = sim.B
    let cols = seeds, rows = maps.count
    let texW = cols * panel, texH = rows * panel
    let viewHalf = Float(240)                           // per-cell camera follows that game's player (tight = big sprites)

    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: texW, height: texH, mipmapped: false)
    td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
    let tex = device.makeTexture(descriptor: td)!

    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for p in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where p.hasSuffix(".png") {
        try? FileManager.default.removeItem(atPath: "\(dir)/\(p)")
    }

    for f in 0 ..< frames.count {
        var inst: [SpriteInstance] = []
        var cells: [SpriteRenderer.GridCell] = []
        for g in 0 ..< N {                                            // each game -> its own viewport cell
            let fr = frames[min(f, endF[g])]
            let animFrame = (f * stride) / 3
            let start = inst.count
            for m in 0 ..< M where fr.monAlive[g * M + m] > 0.5 {
                let p = SIMD2(fr.monPos[(g * M + m) * 2], fr.monPos[(g * M + m) * 2 + 1])
                let v = SIMD2(fr.monVel[(g * M + m) * 2], fr.monVel[(g * M + m) * 2 + 1])
                let tid = sim.monType[g][m]
                inst.append(SpriteInstance(pos: p, rot: atan2f(v.y, v.x) + (rotOffsets[tid] ?? .pi / 4),
                                           size: sim.monBox[g][m] * 0.8, slice: sprites.monsterSlice(tid, animFrame), pad: 0))
            }
            for b in 0 ..< B where fr.bulAlive[g * B + b] > 0.5 {
                let p = SIMD2(fr.bulPos[(g * B + b) * 2], fr.bulPos[(g * B + b) * 2 + 1])
                let v = SIMD2(fr.bulVel[(g * B + b) * 2], fr.bulVel[(g * B + b) * 2 + 1])
                inst.append(SpriteInstance(pos: p, rot: atan2f(v.y, v.x), size: 7, slice: sprites.bulletSlice, pad: 0))
            }
            let pp = SIMD2(fr.player[g * 2], fr.player[g * 2 + 1])
            let aim = SIMD2(fr.playerAim[g * 2], fr.playerAim[g * 2 + 1])
            inst.append(SpriteInstance(pos: pp, rot: atan2f(aim.y, aim.x) - .pi / 2,
                                       size: world.player_radius * 1.3, slice: sprites.playerSlice, pad: 0))
            let row = g / cols, col = g % cols
            let bd = 3.0                                              // inset each cell -> dark border between games
            cells.append(SpriteRenderer.GridCell(
                x: Double(col * panel) + bd, y: Double(row * panel) + bd, w: Double(panel) - 2 * bd, h: Double(panel) - 2 * bd,
                camCenter: pp, camHalf: SIMD2(viewHalf, viewHalf), start: start, count: inst.count - start))
        }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = tex
        rp.colorAttachments[0].loadAction = .clear
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1)
        rp.colorAttachments[0].storeAction = .store
        let cmd = queue.makeCommandBuffer()!
        sprites.encodeGrid(into: cmd, rp: rp, instances: inst, cells: cells)
        cmd.commit(); cmd.waitUntilCompleted()
        writePNG(tex, String(format: "%@/f%04d.png", dir, f))
    }
    print("grid: wrote \(frames.count) frames -> \(dir) (\(cols)x\(rows), panel \(panel)px)")
}

// Parity replay: run the exported games through the (one) batched sim at N=1 and dump trajectories for
// torchsim/parity_diff.py. `monstro-game --port <dir>`.
func runPort() {
    let args = CommandLine.arguments
    func val(_ k: String, _ d: String) -> String {
        if let i = args.firstIndex(of: k), i + 1 < args.count { return args[i + 1] }; return d
    }
    let dir = val("--port", "parity")
    guard let player = MLXMLP(path: val("--player", "\(dir)/../../MonstroSim/models/player.json")),
          let enemy = MLXMLP(path: val("--enemy", "\(dir)/../../MonstroSim/models/monster.json")) else {
        FileHandle.standardError.write("port: no models\n".data(using: .utf8)!); exit(1)
    }
    let dec = JSONDecoder(), enc = JSONEncoder()
    func load<T: Decodable>(_ p: String) -> T { try! dec.decode(T.self, from: Data(contentsOf: URL(fileURLWithPath: p))) }
    let idx: IndexJSON = load("\(dir)/index.json")
    let world: WorldJSON = load("\(dir)/world.json")
    for gid in idx.games {
        let sched: SchedJSON = load("\(dir)/sched_\(gid).json")
        let sim = GridSim(w: world, scheds: [sched], player: player, enemy: enemy)
        let frames = sim.parityRun()
        try! enc.encode(frames).write(to: URL(fileURLWithPath: "\(dir)/swift_\(gid).json"))
        print("  \(gid): ticks=\(frames.count) kills=\(frames.last?.kills ?? 0) hp=\(Int(max(frames.last?.hp ?? 0, 0)))")
    }
    print("wrote swift_*.json -> \(dir)/ (GridSim N=1)")
}
