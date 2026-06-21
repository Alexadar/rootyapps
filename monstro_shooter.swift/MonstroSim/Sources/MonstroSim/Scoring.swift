import Foundation

// MARK: - Episode runner
public enum Runner {
    public static func runEpisode(data: GameData, level: SimLevel, weaponID: Int, exoID: Int,
                                  seed: UInt64, config: EpisodeConfig, policy: Policy) -> EpisodeResult {
        let world = World(data: data, level: level, weaponID: weaponID, exoID: exoID, seed: seed, config: config)
        _ = world.reset()
        var steps = 0
        let maxSteps = Int(config.maxSeconds / SimConstants.tickDelta) + 2
        while steps < maxSteps {
            let action = policy.act(world)
            let r = world.step(action)
            steps += 1
            if r.done { break }
        }
        return world.result
    }

    /// Run `seeds.count` episodes (one per seed) of the same map/policy.
    public static func evaluate(data: GameData, level: SimLevel, weaponID: Int, exoID: Int,
                                seeds: [UInt64], config: EpisodeConfig, makePolicy: (UInt64) -> Policy) -> [EpisodeResult] {
        seeds.map { seed in
            runEpisode(data: data, level: level, weaponID: weaponID, exoID: exoID,
                       seed: seed, config: config, policy: makePolicy(seed))
        }
    }
}

// MARK: - Difficulty + fun/playability scoring
// Difficulty and "fun" are made measurable here. Research (Lily's Garden, modl.ai, King)
// shows a weak/scripted agent's BEST-CASE (top-percentile) runs correlate strongly with
// human-perceived difficulty — so we lean on best-case clear/survival, not the mean.
public struct DifficultyReport {
    public var episodes: Int
    public var deathRate: Double
    public var winRate: Double
    public var meanSurvival: Double
    public var bestCaseSurvival: Double      // top run
    public var meanClearFraction: Double
    public var bestCaseClearFraction: Double // top run — the load-bearing difficulty signal
    public var meanDamageTaken: Double
    public var survivalStdev: Double         // consistency across seeds (fairness input)

    /// 0 (trivial) .. 1 (brutal). High when even the best run can't clear and deaths are common.
    public var difficulty: Double {
        let unclearable = 1 - bestCaseClearFraction
        return min(max(0.6 * unclearable + 0.4 * deathRate, 0), 1)
    }
}

public struct FunReport {
    public var challengeBalance: Double  // peaks when difficulty sits in the target flow band
    public var pacingVariety: Double     // ebb-and-flow of monster pressure (flat = boring)
    public var engagement: Double        // active shooting/killing vs idle
    public var fairness: Double          // consistent outcomes across seeds (not RNG lottery)
    public var progression: Double       // pressure ramps over time

    /// Weighted composite "fun"/playability proxy in 0..1. These weights are hyperparameters.
    public var fun: Double {
        0.35 * challengeBalance + 0.20 * pacingVariety + 0.20 * engagement
            + 0.15 * fairness + 0.10 * progression
    }
}

public enum Scoring {
    public static func difficulty(_ eps: [EpisodeResult]) -> DifficultyReport {
        let n = max(eps.count, 1)
        let survivals = eps.map { $0.survivalTime }
        let clears = eps.map { $0.clearFraction }
        let meanSurv = survivals.reduce(0, +) / Double(n)
        return DifficultyReport(
            episodes: eps.count,
            deathRate: Double(eps.filter { $0.died }.count) / Double(n),
            winRate: Double(eps.filter { $0.victory }.count) / Double(n),
            meanSurvival: meanSurv,
            bestCaseSurvival: survivals.max() ?? 0,
            meanClearFraction: clears.reduce(0, +) / Double(n),
            bestCaseClearFraction: clears.max() ?? 0,
            meanDamageTaken: eps.map { $0.damageTaken }.reduce(0, +) / Double(n),
            survivalStdev: stdev(survivals)
        )
    }

    public static func fun(_ eps: [EpisodeResult], targetDifficulty: Double,
                           band: Double = 0.25) -> FunReport {
        let diff = difficulty(eps).difficulty
        // Challenge balance: 1 at target, decaying outside the band.
        let challenge = max(0, 1 - abs(diff - targetDifficulty) / band)

        // Pacing variety: normalized variability of per-second pressure, averaged across episodes.
        let pacing = mean(eps.map { ep -> Double in
            guard ep.pressureSamples.count > 2 else { return 0 }
            let s = stdev(ep.pressureSamples), m = mean(ep.pressureSamples)
            let cv = m > 0 ? s / m : 0                // coefficient of variation
            return min(cv, 1)                         // some variety good; cap
        })

        // Engagement: accuracy as a proxy for active, aimed play (low idle/spray).
        let engagement = mean(eps.map { min($0.accuracy * 1.5, 1) })

        // Fairness: low survival variance across seeds => outcomes driven by skill/map, not RNG.
        let rep = difficulty(eps)
        let fairness = rep.meanSurvival > 0 ? max(0, 1 - rep.survivalStdev / rep.meanSurvival) : 0

        // Progression: positive correlation of pressure with time (ramp up).
        let progression = mean(eps.map { rampScore($0.pressureSamples) })

        return FunReport(challengeBalance: challenge, pacingVariety: pacing,
                         engagement: engagement, fairness: fairness, progression: progression)
    }

    // MARK: helpers
    static func mean(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
    static func stdev(_ a: [Double]) -> Double {
        guard a.count > 1 else { return 0 }
        let m = mean(a)
        return (a.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(a.count - 1)).squareRoot()
    }
    /// Pearson correlation of pressure vs. index, mapped to 0..1 (0.5 = flat).
    static func rampScore(_ p: [Double]) -> Double {
        guard p.count > 2 else { return 0.5 }
        let xs = (0..<p.count).map { Double($0) }
        let mx = mean(xs), my = mean(p)
        var num = 0.0, dx = 0.0, dy = 0.0
        for i in 0..<p.count { num += (xs[i] - mx) * (p[i] - my); dx += pow(xs[i] - mx, 2); dy += pow(p[i] - my, 2) }
        let denom = (dx * dy).squareRoot()
        let r = denom > 0 ? num / denom : 0
        return (r + 1) / 2
    }
}
