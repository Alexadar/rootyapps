import Foundation
import MonstroSim
import MonstroSimGPU

// GPU-only CLI. The same MonstroSimGPU engine (BatchWorld + GPUPolicy) is shared by the trainer
// and (later) the game — training uses N envs + ES + per-episode sync; the game will use the same
// BatchWorld at N=1 + per-frame sync. Models are detached artifacts (JSON weights).
//
//   monstrosim gputrain  --map m.json [--envs 512] [--ticks 400] [--pop 20] [--iters 40] [--out player.json]
//   monstrosim gpueval   --map m.json --net player.json        (trained vs random, held-out seeds)
//   monstrosim gprun     --map m.json [--net models/player.json] [--envs 64] [--ticks 600]   (run a shipped model)
//   monstrosim gpubench  --map m.json [--envs 4096] [--steps 200]
//   monstrosim gpuprofile --map m.json [--envs 1024] [--steps 60]

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
            i += (val == "true" && (i + 1 >= a.count || a[i + 1].hasPrefix("--"))) ? 1 : 2
        } else { i += 1 }
    }
    return (cmd, opts)
}

func secs(_ block: () -> Void) -> Double {
    let t0 = DispatchTime.now(); block()
    return Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e9
}

func loadNet(_ path: String?) -> GPUPolicy? {
    guard let path = path, let d = FileManager.default.contents(atPath: path) else { return nil }
    return GPUPolicy.fromData(d)
}

let playerSizes = [GPUPolicy.playerObsSize(), 64, 64, GPUPolicy.playerOutSize()]

let (cmd, opts) = args()
let client = opts["client"] ?? "../monstro_client"
let data = GameData.load(clientRoot: client)
if data.monsters.isEmpty {
    fputs("No monster configs under \(client)/Assets/configs/monsters. Pass --client <monstro_client dir>.\n", stderr)
    exit(1)
}
func loadMapOrExit(_ what: String) -> SimLevel {
    guard let p = opts["map"], let m = ConfigLoader.loadMap(path: p) else {
        fputs("\(what) requires --map <map.json>\n", stderr); exit(1)
    }
    return SimLevel(m)
}
let weapon = data.weapons[1] ?? data.weapons.values.first!
let exo = data.exoskeletons[1] ?? data.exoskeletons.values.first!

switch cmd {
case "gputrain":
    let level = loadMapOrExit("gputrain")
    let nEnvs = Int(opts["envs"] ?? "512") ?? 512
    let ticks = Int(opts["ticks"] ?? "400") ?? 400
    let bw = BatchWorld(schedule: SpawnSchedule(level: level, data: data, baseSeed: 1, nEnvs: nEnvs),
                        weapon: weapon, exo: exo)
    var es = GPUES.Config()
    es.iterations = Int(opts["iters"] ?? "40") ?? 40
    es.population = Int(opts["pop"] ?? "20") ?? 20
    let net0 = GPUPolicy(sizes: playerSizes, seed: 7)
    print("GPU ES: N=\(nEnvs) seeds × \(ticks) ticks/episode, pop=\(es.population), iters=\(es.iterations)")
    let trained = GPUES.train(net0: net0, cfg: es, seed: 42, fitness: { net in
        let r = bw.rolloutPlayer(net: net, ticks: ticks)
        return r.reduce(0, +) / Float(r.count)
    }, onIteration: { it, center, popBest in
        print(String(format: "iter %3d  center %.2f  popBest %.2f", it, center, popBest))
    })
    let out = opts["out"] ?? "player.json"
    try? trained.toData().write(to: URL(fileURLWithPath: out))
    let final = bw.rolloutPlayerFull(net: trained, ticks: ticks)
    print(String(format: "Trained -> %@  reward %.2f  kills %.2f  survive %.0f%%", out, final.meanReward, final.meanKills, final.surviveRate * 100))

case "gpueval":
    let level = loadMapOrExit("gpueval")
    let nEnvs = Int(opts["envs"] ?? "256") ?? 256
    let ticks = Int(opts["ticks"] ?? "400") ?? 400
    let bw = BatchWorld(schedule: SpawnSchedule(level: level, data: data, baseSeed: 9000, nEnvs: nEnvs),  // held-out seeds
                        weapon: weapon, exo: exo)
    func report(_ tag: String, _ net: GPUPolicy) {
        let r = bw.rolloutPlayerFull(net: net, ticks: ticks)
        print("  \(tag.padding(toLength: 8, withPad: " ", startingAt: 0)) " +
              String(format: "reward %.2f   kills %.2f   survive %.0f%%", r.meanReward, r.meanKills, r.surviveRate * 100))
    }
    print("Held-out eval (\(nEnvs) seeds × \(ticks) ticks):")
    report("random", GPUPolicy(sizes: playerSizes, seed: 999))
    if let net = loadNet(opts["net"]) { report("trained", net) }
    else { print("  (pass --net player.json to compare a trained model)") }

case "gprun":
    // Run a SHIPPED model through the shared engine (the game's inference path, headless for now).
    let level = loadMapOrExit("gprun")
    let nEnvs = Int(opts["envs"] ?? "64") ?? 64
    let ticks = Int(opts["ticks"] ?? "600") ?? 600
    let netPath = opts["net"] ?? "models/player.json"
    guard let net = loadNet(netPath) else { fputs("gprun: could not load model at \(netPath)\n", stderr); exit(1) }
    let bw = BatchWorld(schedule: SpawnSchedule(level: level, data: data, baseSeed: 5000, nEnvs: nEnvs),
                        weapon: weapon, exo: exo)
    let r = bw.rolloutPlayerFull(net: net, ticks: ticks)
    print("Shipped model \(netPath) on \(level.name):")
    print(String(format: "  reward %.2f   kills %.2f   survive %.0f%%   (%d envs × %d ticks)", r.meanReward, r.meanKills, r.surviveRate * 100, nEnvs, ticks))

case "gpubench":
    let level = loadMapOrExit("gpubench")
    let steps = Int(opts["steps"] ?? "200") ?? 200
    print("GPU throughput (fused step):")
    let sweep: [Int] = opts["envs"].flatMap { Int($0) }.map { [$0] } ?? [256, 1024, 4096]
    for nEnvs in sweep {
        let sched = SpawnSchedule(level: level, data: data, baseSeed: 1, nEnvs: nEnvs)
        let bw = BatchWorld(schedule: sched, weapon: weapon, exo: exo)
        bw.forceDenseActivation(); bw.stepFused()   // warm up
        let s = secs { for _ in 0..<steps { bw.stepFused() }; _ = bw.readback() }
        print(String(format: "  %5d env: %.0f env-steps/sec  [M=%d]", nEnvs, Double(nEnvs * steps) / s, sched.maxMon))
    }

case "gpuprofile":
    let level = loadMapOrExit("gpuprofile")
    let nEnvs = Int(opts["envs"] ?? "1024") ?? 1024
    let steps = Int(opts["steps"] ?? "60") ?? 60
    let bw = BatchWorld(schedule: SpawnSchedule(level: level, data: data, baseSeed: 1, nEnvs: nEnvs),
                        weapon: weapon, exo: exo)
    bw.forceDenseActivation(); _ = bw.profileStep()
    var totals: [String: Double] = [:]
    for _ in 0..<steps { for (label, s) in bw.profileStep() { totals[label, default: 0] += s } }
    let grand = totals.values.reduce(0, +)
    print("Profile: N=\(nEnvs), M=\(bw.m), B=128, \(steps) dense steps")
    for (label, s) in totals.sorted(by: { $0.value > $1.value }) {
        print("  \(label.padding(toLength: 20, withPad: " ", startingAt: 0)) \(String(format: "%7.1f ms  %5.1f%%", s * 1000, s / grand * 100))")
    }

default:
    print("""
    MonstroSim — GPU-only headless engine (training + game share it)

      gputrain   --map m.json [--envs 512] [--ticks 400] [--pop 20] [--iters 40] [--out player.json]
      gpueval    --map m.json --net player.json          trained vs random on held-out seeds
      gprun      --map m.json [--net models/player.json]  run a shipped model through the engine
      gpubench   --map m.json [--envs 4096] [--steps 200] fused-step throughput
      gpuprofile --map m.json [--envs 1024]               per-phase GPU time breakdown

    --client defaults to ../monstro_client. Build metallib once per GPU_SETUP.md.
    """)
}
