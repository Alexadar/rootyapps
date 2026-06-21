import Foundation
import MonstroSim
import MonstroSimGPU

// Minimal dependency-free CLI:
//   monstrosim eval       --client <root> --map <map.json> --policy kiter --episodes 20 --seed 1
//   monstrosim train      --client <root> --map <map.json> --iterations 30 --out net.json
//   monstrosim autoconfig --client <root> --examples a.json,b.json --target 0.5 --fun 0.5 --policy kiter --out gen.json

func args() -> (cmd: String, opts: [String: String]) {
    var a = Array(CommandLine.arguments.dropFirst())
    let cmd = a.first ?? "help"
    if !a.isEmpty { a.removeFirst() }
    var opts: [String: String] = [:]
    var i = 0
    while i < a.count {
        if a[i].hasPrefix("--") {
            let key = String(a[i].dropFirst(2))
            let val = (i + 1 < a.count && !a[i + 1].hasPrefix("--")) ? a[i + 1] : "true"
            opts[key] = val
            i += val == "true" && (i + 1 >= a.count || a[i + 1].hasPrefix("--")) ? 1 : 2
        } else { i += 1 }
    }
    return (cmd, opts)
}

func defaultClient(_ opts: [String: String]) -> String {
    opts["client"] ?? "../monstro_client"
}

func makePolicy(_ name: String, net: MLP?, seed: UInt64) -> Policy {
    switch name {
    case "random": return RandomPolicy(seed: seed)
    case "idle": return IdlePolicy()
    case "net":
        guard let net = net else { fputs("net policy requires --net <file>\n", stderr); exit(1) }
        return NeuralPolicy(net)
    default: return KiterPolicy()
    }
}

func loadNet(_ path: String?) -> MLP? {
    guard let path = path, let data = FileManager.default.contents(atPath: path) else { return nil }
    struct Saved: Codable { let sizes: [Int]; let params: [Float] }
    guard let s = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
    return MLP(sizes: s.sizes, params: s.params)
}

func saveNet(_ net: MLP, _ path: String) {
    struct Saved: Codable { let sizes: [Int]; let params: [Float] }
    let enc = JSONEncoder()
    if let d = try? enc.encode(Saved(sizes: net.sizes, params: net.params)) {
        try? d.write(to: URL(fileURLWithPath: path))
    }
}

let (cmd, opts) = args()
let client = defaultClient(opts)
let data = GameData.load(clientRoot: client)

if data.monsters.isEmpty {
    fputs("No monster configs found under \(client)/Assets/configs/monsters. Pass --client <monstro_client dir>.\n", stderr)
    exit(1)
}

switch cmd {
case "eval":
    guard let mapPath = opts["map"], let map = ConfigLoader.loadMap(path: mapPath) else {
        fputs("eval requires --map <map.json>\n", stderr); exit(1)
    }
    let level = SimLevel(map)
    let episodes = Int(opts["episodes"] ?? "20") ?? 20
    let baseSeed = UInt64(opts["seed"] ?? "1") ?? 1
    let net = loadNet(opts["net"])
    let policyName = opts["policy"] ?? "kiter"
    let cfg = EpisodeConfig(maxSeconds: Double(opts["max-seconds"] ?? "120") ?? 120)
    let seeds = (0..<episodes).map { baseSeed &+ UInt64($0) }
    let eps = Runner.evaluate(data: data, level: level, weaponID: Int(opts["weapon"] ?? "1") ?? 1,
                              exoID: Int(opts["exo"] ?? "1") ?? 1, seeds: seeds, config: cfg) { seed in
        makePolicy(policyName, net: net, seed: seed)
    }
    let diff = Scoring.difficulty(eps)
    let fun = Scoring.fun(eps, targetDifficulty: Double(opts["target"] ?? "0.5") ?? 0.5)
    print("Map: \(level.name)  (\(level.waves.count) waves, expected \(level.expectedTotal) monsters)")
    print("Policy: \(policyName)  Episodes: \(episodes)")
    print(String(format: "  win rate         %.2f", diff.winRate))
    print(String(format: "  death rate       %.2f", diff.deathRate))
    print(String(format: "  mean survival    %.1fs", diff.meanSurvival))
    print(String(format: "  best-case clear  %.2f", diff.bestCaseClearFraction))
    print(String(format: "  mean damage      %.1f", diff.meanDamageTaken))
    print(String(format: "  DIFFICULTY       %.2f", diff.difficulty))
    print(String(format: "  fun: challenge %.2f pacing %.2f engage %.2f fair %.2f progress %.2f",
                 fun.challengeBalance, fun.pacingVariety, fun.engagement, fun.fairness, fun.progression))
    print(String(format: "  FUN              %.2f", fun.fun))

case "train":
    // One map (--map) OR several (--maps a.json,b.json,...). Training across maps =
    // domain randomization -> a generalist agent instead of one that memorizes a single map.
    let mapArg = opts["maps"] ?? opts["map"]
    guard let mapArg else { fputs("train requires --map <map.json> or --maps a.json,b.json\n", stderr); exit(1) }
    let mapPaths = mapArg.split(separator: ",").map(String.init)
    let levels = mapPaths.compactMap { ConfigLoader.loadMap(path: $0).map(SimLevel.init) }
    guard !levels.isEmpty else { fputs("train: no maps could be loaded\n", stderr); exit(1) }

    var es = ESConfig()
    es.iterations = Int(opts["iterations"] ?? "30") ?? 30
    es.population = Int(opts["population"] ?? "48") ?? 48
    let cfg = EpisodeConfig(maxSeconds: Double(opts["max-seconds"] ?? "60") ?? 60)
    let seedsPerMap = Int(opts["seeds"] ?? "2") ?? 2
    let trainSeeds = (0..<seedsPerMap).map { UInt64($0) &+ 7 }
    let obsSize = World.observationSize(nearestK: cfg.nearestK)
    let actSize = SimAction.moveDirs + SimAction.aimDirs + 2
    print("Training across \(levels.count) map(s) × \(seedsPerMap) seed(s) = \(levels.count * seedsPerMap) episodes/eval")

    let net = ES.train(observationSize: obsSize, actionSize: actSize, cfg: es, seed: 42, fitness: { mlp in
        let policy = NeuralPolicy(mlp)
        var total = 0.0
        for level in levels {
            for s in trainSeeds {
                let r = Runner.runEpisode(data: data, level: level, weaponID: 1, exoID: 1, seed: s, config: cfg, policy: policy)
                total += r.totalReward
            }
        }
        return total / Double(levels.count * trainSeeds.count)
    }, onIteration: { it, best in
        print(String(format: "iter %3d  best mean reward %.2f", it, best))
    })

    let out = opts["out"] ?? "net.json"
    saveNet(net, out)
    print("Saved policy -> \(out)  (params: \(net.params.count))")

case "autoconfig":
    let examplePaths = (opts["examples"] ?? "").split(separator: ",").map(String.init)
    let examples = examplePaths.compactMap { ConfigLoader.loadMap(path: $0) }
    guard !examples.isEmpty else { fputs("autoconfig requires --examples a.json,b.json\n", stderr); exit(1) }
    var settings = AutoConfigSettings()
    settings.targetDifficulty = Double(opts["target"] ?? "0.5") ?? 0.5
    settings.funWeight = Double(opts["fun"] ?? "0.5") ?? 0.5
    settings.generations = Int(opts["generations"] ?? "12") ?? 12
    settings.population = Int(opts["population"] ?? "16") ?? 16
    settings.evalSeeds = Int(opts["seeds"] ?? "6") ?? 6
    let net = loadNet(opts["net"])
    let policyName = opts["policy"] ?? "kiter"

    print("Autoconfig: target difficulty \(settings.targetDifficulty), fun weight \(settings.funWeight)")
    let result = AutoConfig.run(data: data, examples: examples, settings: settings, seed: 1, makePolicy: { seed in
        makePolicy(policyName, net: net, seed: seed)
    }, onGeneration: { gen, score, diff, fun in
        print(String(format: "gen %2d  score %.3f  difficulty %.2f  fun %.2f", gen, score, diff, fun))
    })

    let out = opts["out"] ?? "generated_map.json"
    try? ConfigLoader.saveMap(result.map, path: out)
    print(String(format: "Best map -> %@  difficulty %.2f  fun %.2f", out, result.difficulty.difficulty, result.fun.fun))
    print("  params: waves \(result.params.numWaves), firstCount \(result.params.firstCount), growth \(String(format: "%.2f", result.params.countGrowth)), types \(result.params.typeIDs)")

case "bench":
    // GPU env-steps/sec (N parallel envs) vs CPU single-env, same scripted kite dynamics.
    guard let mapPath = opts["map"], let map = ConfigLoader.loadMap(path: mapPath) else {
        fputs("bench requires --map <map.json>\n", stderr); exit(1)
    }
    let level = SimLevel(map)
    let steps = Int(opts["steps"] ?? "300") ?? 300
    let weapon = data.weapons[1]!, exo = data.exoskeletons[1]!

    func secs(_ block: () -> Void) -> Double {
        let t0 = DispatchTime.now(); block()
        return Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9
    }

    // CPU single-env baseline (scripted kiter).
    let cpuWorld = World(data: data, level: level, weaponID: 1, exoID: 1, seed: 1,
                         config: EpisodeConfig(maxSeconds: 9999))
    _ = cpuWorld.reset()
    let kiter = KiterPolicy()
    let cpuSecs = secs { for _ in 0..<steps { _ = cpuWorld.step(kiter.act(cpuWorld)) } }
    let cpuRate = Double(steps) / cpuSecs
    print(String(format: "CPU  1 env   : %.0f env-steps/sec  (%d steps in %.2fs)", cpuRate, steps, cpuSecs))

    print("GPU batches (env-steps/sec = N × batch-steps/sec):")
    let fused = opts["fused"] != "false"   // default: fused (mx.compile); --fused false for unfused
    let envSweep: [Int] = opts["envs"].flatMap { Int($0) }.map { [$0] } ?? [256, 1024, 4096, 16384]
    for nEnvs in envSweep {
        let sched = SpawnSchedule(level: level, data: data, baseSeed: 1, nEnvs: nEnvs)
        let bw = BatchWorld(schedule: sched, weapon: weapon, exo: exo)
        bw.forceDenseActivation()
        if fused { bw.stepFused() } else { bw.step() }   // warm up (JIT / compile)
        let gpuSecs = secs { for _ in 0..<steps { if fused { bw.stepFused() } else { bw.step() } }; _ = bw.readback() }
        let envRate = Double(nEnvs * steps) / gpuSecs
        print(String(format: "GPU%@ %5d env: %.0f env-steps/sec  (%.1fx CPU)  [M=%d]",
                     fused ? "(fused)" : "(plain)", nEnvs, envRate, envRate / cpuRate, sched.maxMon))
    }

case "gputrain":
    // Phase B: train the player net fully on-device with ES (per-episode sync).
    guard let mapPath = opts["map"], let map = ConfigLoader.loadMap(path: mapPath) else {
        fputs("gputrain requires --map <map.json>\n", stderr); exit(1)
    }
    let level = SimLevel(map)
    let nEnvs = Int(opts["envs"] ?? "512") ?? 512
    let ticks = Int(opts["ticks"] ?? "200") ?? 200
    let sched = SpawnSchedule(level: level, data: data, baseSeed: 1, nEnvs: nEnvs)
    let bw = BatchWorld(schedule: sched, weapon: data.weapons[1]!, exo: data.exoskeletons[1]!)
    var es = GPUES.Config()
    es.iterations = Int(opts["iters"] ?? "20") ?? 20
    es.population = Int(opts["pop"] ?? "16") ?? 16
    let net0 = GPUPolicy(sizes: [GPUPolicy.playerObsSize(), 64, 64, GPUPolicy.playerOutSize()], seed: 7)
    print("GPU ES: N=\(nEnvs) seeds × \(ticks) ticks/episode, pop=\(es.population), iters=\(es.iterations)")
    let t0 = DispatchTime.now()
    let trained = GPUES.train(net0: net0, cfg: es, seed: 42, fitness: { net in
        let r = bw.rolloutPlayer(net: net, ticks: ticks)
        return r.reduce(0, +) / Float(r.count)
    }, onIteration: { it, center, popBest in
        print(String(format: "iter %3d  center %.2f  popBest %.2f", it, center, popBest))
    })
    let secs = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9
    let out = opts["out"] ?? "gpu_player.json"
    try? trained.toData().write(to: URL(fileURLWithPath: out))
    // final eval
    let finalR = bw.rolloutPlayer(net: trained, ticks: ticks)
    print(String(format: "Trained -> %@  final mean reward %.2f  (%.0fs)", out, finalR.reduce(0, +) / Float(finalR.count), secs))

case "gpueval":
    // Does it play correctly? Trained net vs random baseline on HELD-OUT seeds.
    guard let mapPath = opts["map"], let map = ConfigLoader.loadMap(path: mapPath) else {
        fputs("gpueval requires --map <map.json>\n", stderr); exit(1)
    }
    let level = SimLevel(map)
    let nEnvs = Int(opts["envs"] ?? "256") ?? 256
    let ticks = Int(opts["ticks"] ?? "400") ?? 400
    let sched = SpawnSchedule(level: level, data: data, baseSeed: 9000, nEnvs: nEnvs)  // held-out seeds
    let bw = BatchWorld(schedule: sched, weapon: data.weapons[1]!, exo: data.exoskeletons[1]!)
    let randomNet = GPUPolicy(sizes: [GPUPolicy.playerObsSize(), 64, 64, GPUPolicy.playerOutSize()], seed: 999)
    func report(_ tag: String, _ net: GPUPolicy) {
        let r = bw.rolloutPlayerFull(net: net, ticks: ticks)
        print(String(format: "  %-8s reward %.2f   kills %.2f   survive %.0f%%", (tag as NSString).utf8String!, r.meanReward, r.meanKills, r.surviveRate * 100))
    }
    print("Held-out eval (\(nEnvs) seeds × \(ticks) ticks):")
    report("random", randomNet)
    if let path = opts["net"], let d = FileManager.default.contents(atPath: path), let net = GPUPolicy.fromData(d) {
        report("trained", net)
    }

case "gpuroll":
    // Phase A smoke: random player net, on-device episode, ONE sync. Prints reward + throughput.
    guard let mapPath = opts["map"], let map = ConfigLoader.loadMap(path: mapPath) else {
        fputs("gpuroll requires --map <map.json>\n", stderr); exit(1)
    }
    let level = SimLevel(map)
    let nEnvs = Int(opts["envs"] ?? "1024") ?? 1024
    let ticks = Int(opts["ticks"] ?? "300") ?? 300
    let sched = SpawnSchedule(level: level, data: data, baseSeed: 1, nEnvs: nEnvs)
    let bw = BatchWorld(schedule: sched, weapon: data.weapons[1]!, exo: data.exoskeletons[1]!)
    let net = GPUPolicy(sizes: [GPUPolicy.playerObsSize(), 64, 64, GPUPolicy.playerOutSize()], seed: 7)
    _ = bw.rolloutPlayer(net: net, ticks: 8)   // warm up / compile
    let t0 = DispatchTime.now()
    let rewards = bw.rolloutPlayer(net: net, ticks: ticks)
    let secs = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9
    let mean = rewards.reduce(0, +) / Float(rewards.count)
    print(String(format: "Phase A: N=%d envs × %d ticks, ONE sync/episode", nEnvs, ticks))
    print(String(format: "  mean episode reward: %.2f", mean))
    print(String(format: "  throughput: %.0f env-steps/sec  (%.3fs)", Double(nEnvs * ticks) / secs, secs))

case "profile":
    // Per-phase GPU time breakdown in the dense (all-active) regime.
    guard let mapPath = opts["map"], let map = ConfigLoader.loadMap(path: mapPath) else {
        fputs("profile requires --map <map.json>\n", stderr); exit(1)
    }
    let level = SimLevel(map)
    let nEnvs = Int(opts["envs"] ?? "1024") ?? 1024
    let steps = Int(opts["steps"] ?? "60") ?? 60
    let sched = SpawnSchedule(level: level, data: data, baseSeed: 1, nEnvs: nEnvs)
    let bw = BatchWorld(schedule: sched, weapon: data.weapons[1]!, exo: data.exoskeletons[1]!)
    bw.forceDenseActivation()
    _ = bw.profileStep()   // warm up
    var totals: [String: Double] = [:]
    for _ in 0..<steps { for (label, s) in bw.profileStep() { totals[label, default: 0] += s } }
    let grand = totals.values.reduce(0, +)
    print("Profile: N=\(nEnvs) envs, M=\(sched.maxMon) monsters, B=128 bullets, \(steps) dense steps")
    for (label, s) in totals.sorted(by: { $0.value > $1.value }) {
        let name = label.padding(toLength: 20, withPad: " ", startingAt: 0)
        print("  \(name) \(String(format: "%7.1f", s * 1000)) ms   \(String(format: "%5.1f", s / grand * 100))%")
    }
    print("  \("TOTAL".padding(toLength: 20, withPad: " ", startingAt: 0)) \(String(format: "%7.1f", grand * 1000)) ms")

case "parity":
    // Rule-parity: CPU over K seeds vs GPU with K envs on the same map; compare aggregates.
    guard let mapPath = opts["map"], let map = ConfigLoader.loadMap(path: mapPath) else {
        fputs("parity requires --map <map.json>\n", stderr); exit(1)
    }
    let level = SimLevel(map)
    let k = Int(opts["envs"] ?? "64") ?? 64
    let secsCap = Double(opts["max-seconds"] ?? "30") ?? 30
    let stepN = Int(secsCap / SimConstants.tickDelta)
    let weapon = data.weapons[1]!, exo = data.exoskeletons[1]!

    // CPU: K seeds, scripted kiter.
    var cpuKills = 0.0, cpuDead = 0.0
    for s in 0..<k {
        let r = Runner.runEpisode(data: data, level: level, weaponID: 1, exoID: 1,
                                  seed: UInt64(s), config: EpisodeConfig(maxSeconds: secsCap), policy: KiterPolicy())
        cpuKills += Double(r.kills); cpuDead += r.died ? 1 : 0
    }
    // GPU: K envs (seeds 0..<K via schedule baseSeed 0).
    let sched = SpawnSchedule(level: level, data: data, baseSeed: 0, nEnvs: k)
    let bw = BatchWorld(schedule: sched, weapon: weapon, exo: exo)
    for _ in 0..<stepN { bw.step() }
    let (hp, kills) = bw.readback()
    let gpuKills = kills.reduce(0, +) / Float(k)
    let gpuDead = Double(hp.filter { $0 <= 0 }.count) / Double(k)

    print("Rule-parity (map \(level.name), \(k) seeds/envs, \(Int(secsCap))s):")
    print(String(format: "  mean kills   CPU %.1f   GPU %.1f", cpuKills / Double(k), gpuKills))
    print(String(format: "  death rate   CPU %.2f   GPU %.2f", cpuDead / Double(k), gpuDead))

default:
    print("""
    MonstroSim — headless playtest / train / generate / GPU

    Commands:
      eval        --client <root> --map <map.json> [--policy kiter|idle|random|net] [--net f] [--episodes 20] [--seed 1]
      train       --client <root> (--map <m.json> | --maps a.json,b.json) [--seeds 2] [--iterations 30] [--population 48] [--max-seconds 60] [--out net.json]
      autoconfig  --client <root> --examples a.json,b.json [--target 0.5] [--fun 0.5] [--policy kiter|net] [--net f] [--out gen.json]

    <root> defaults to ../monstro_client
    """)
}
