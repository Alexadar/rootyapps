import Foundation

// Procedural map generation ("autoconfig"): parameterize a map, then search the parameters
// to hit a target difficulty while maximizing the fun/playability score — using the sim +
// a policy (scripted OR a trained agent) as the fitness function. This is generate-and-test
// / experience-driven PCG. Output is a real map_XXXX.json the shipping game loads.

// MARK: - Parameterized map
public struct MapParams {
    public var startDelay: Int       // seconds before first wave
    public var numWaves: Int
    public var firstCount: Int       // monsters in wave 0
    public var countGrowth: Double   // per-wave multiplier (>1 ramps up)
    public var spacing: Int          // seconds between waves
    public var typeIDs: [Int]        // monster types available
    public var duration: Int         // landingDuration (episode length)

    public func toMap(id: Int) -> MapCfg {
        var waves: [MapCfg.Wave] = []
        for i in 0..<max(numWaves, 1) {
            let t = startDelay + i * max(spacing, 1)
            let count = max(1, Int((Double(firstCount) * pow(countGrowth, Double(i))).rounded()))
            waves.append(MapCfg.Wave(startTime: t, count: count))
        }
        let types = typeIDs.isEmpty ? [1] : typeIDs
        return MapCfg(id: id, landingDuration: duration,
                      monsterSpawnWaves: waves,
                      monsterTypes: [MapCfg.TypePeriod(startTime: 0, monsterTypeIds: types)],
                      defaultNameLocalizations: ["en-us": "generated \(id)"])
    }

    /// Approximate params from an existing map (to seed the search from real examples).
    public static func from(_ map: MapCfg) -> MapParams {
        let active = map.monsterSpawnWaves.filter { $0.count > 0 }
        let counts = active.map { $0.count }
        let starts = active.map { $0.startTime }.sorted()
        let spacing = starts.count > 1 ? max(1, (starts.last! - starts.first!) / max(1, starts.count - 1)) : 5
        let growth = (counts.count > 1 && counts.first! > 0)
            ? pow(Double(counts.last!) / Double(counts.first!), 1.0 / Double(counts.count - 1)) : 1.0
        return MapParams(
            startDelay: starts.first ?? 1,
            numWaves: max(active.count, 1),
            firstCount: max(counts.first ?? 5, 1),
            countGrowth: min(max(growth, 0.5), 3),
            spacing: spacing,
            typeIDs: map.monsterTypes.flatMap { $0.monsterTypeIds }.uniqued(),
            duration: map.landingDuration
        )
    }

    public func mutated(available: [Int], rng: inout SeededGenerator) -> MapParams {
        var p = self
        func jiggle(_ v: Int, _ d: Int, _ lo: Int, _ hi: Int) -> Int {
            min(max(v + Int.random(in: -d...d, using: &rng), lo), hi)
        }
        p.startDelay = jiggle(startDelay, 2, 0, 20)
        p.numWaves = jiggle(numWaves, 1, 1, 12)
        p.firstCount = jiggle(firstCount, 3, 1, 60)
        p.countGrowth = min(max(countGrowth + Double.random(in: -0.2...0.2, using: &rng), 0.5), 3)
        p.spacing = jiggle(spacing, 3, 2, 30)
        p.duration = jiggle(duration, 5, 20, 240)
        // Occasionally add/remove a monster type.
        if Bool.random(using: &rng), !available.isEmpty {
            if Bool.random(using: &rng) || p.typeIDs.isEmpty {
                let add = available.randomElement(using: &rng)!
                if !p.typeIDs.contains(add) { p.typeIDs.append(add) }
            } else if p.typeIDs.count > 1 {
                p.typeIDs.remove(at: Int.random(in: 0..<p.typeIDs.count, using: &rng))
            }
        }
        return p
    }
}

// MARK: - Autoconfig (evolutionary balance search)
public struct AutoConfigSettings {
    public var targetDifficulty: Double = 0.5
    public var funWeight: Double = 0.5
    public var generations: Int = 12
    public var population: Int = 16
    public var evalSeeds: Int = 6
    public var weaponID: Int = 1
    public var exoID: Int = 1
    public var episodeConfig = EpisodeConfig()
    public init() {}
}

public struct AutoConfigResult {
    public let map: MapCfg
    public let score: Double
    public let difficulty: DifficultyReport
    public let fun: FunReport
    public let params: MapParams
}

public enum AutoConfig {
    /// Search map parameters (seeded from `examples`) to hit target difficulty + maximize fun,
    /// scored by running `makePolicy` through the sim.
    public static func run(data: GameData, examples: [MapCfg], settings: AutoConfigSettings,
                           seed: UInt64, makePolicy: @escaping (UInt64) -> Policy,
                           onGeneration: ((Int, Double, Double, Double) -> Void)? = nil) -> AutoConfigResult {
        var rng = SeededGenerator(seed: seed)
        let available = data.monsters.keys.sorted()
        let seeds = (0..<settings.evalSeeds).map { UInt64($0) &+ 1000 }

        // Seed population from example maps (+ mutations).
        var population: [MapParams] = examples.map { MapParams.from($0) }
        while population.count < settings.population {
            let base = population.randomElement(using: &rng) ?? MapParams.from(examples.first!)
            population.append(base.mutated(available: available, rng: &rng))
        }
        population = Array(population.prefix(settings.population))

        func score(_ p: MapParams) -> AutoConfigResult {
            let level = SimLevel(p.toMap(id: 9000))
            let eps = Runner.evaluate(data: data, level: level, weaponID: settings.weaponID, exoID: settings.exoID,
                                      seeds: seeds, config: settings.episodeConfig, makePolicy: makePolicy)
            let diff = Scoring.difficulty(eps)
            let fun = Scoring.fun(eps, targetDifficulty: settings.targetDifficulty)
            // Maximize: closeness to target difficulty + weighted fun.
            let s = -abs(diff.difficulty - settings.targetDifficulty) + settings.funWeight * fun.fun
            return AutoConfigResult(map: p.toMap(id: 9000), score: s, difficulty: diff, fun: fun, params: p)
        }

        var scored = population.map(score)
        var best = scored.max { $0.score < $1.score }!

        for gen in 0..<settings.generations {
            // Elitist: keep top half, refill by mutating survivors.
            scored.sort { $0.score > $1.score }
            let survivors = Array(scored.prefix(max(2, settings.population / 2)))
            var next = survivors
            while next.count < settings.population {
                let parent = survivors.randomElement(using: &rng)!.params
                next.append(score(parent.mutated(available: available, rng: &rng)))
            }
            scored = next
            if let genBest = scored.max(by: { $0.score < $1.score }), genBest.score > best.score { best = genBest }
            onGeneration?(gen, best.score, best.difficulty.difficulty, best.fun.fun)
        }
        return best
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
