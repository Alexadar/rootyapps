import Foundation

/// The shipped balance artifact: theta (18 calibrated knobs) + the trained
/// dealer weights, from `world_coevolved.json` (co-evolution equilibrium at
/// 62% player win over 480-week episodes).
public struct Theta: Decodable {
    public let pay_mult_meme, pay_mult_normal, pay_mult_hit, pay_mult_cult: Double
    public let release_cost_mult, tour_rev_mult, tour_cost_mult: Double
    public let salary_mult, upgrade_cost_mult, equip_cost_mult, start_money_mult: Double
    public let week_event_chance, artist_event_chance, need_chance: Double
    public let luck_spread_mult, bankruptcy_floor, token_reward_mult, fan_rate_mult: Double

    /// Per-tier pay multiplier; tier 0 (Провал) is untouched by theta.
    public var payMult: [Double] {
        [1.0, pay_mult_meme, pay_mult_normal, pay_mult_hit, pay_mult_cult]
    }

    /// Neutral theta: every multiplier 1, chances at the JSON defaults.
    public static func neutral(_ c: GameConstants) -> Theta {
        Theta(pay_mult_meme: 1, pay_mult_normal: 1, pay_mult_hit: 1, pay_mult_cult: 1,
              release_cost_mult: 1, tour_rev_mult: 1, tour_cost_mult: 1,
              salary_mult: 1, upgrade_cost_mult: 1, equip_cost_mult: 1, start_money_mult: 1,
              week_event_chance: c.weekly.weekEventChance,
              artist_event_chance: c.weekly.artistEventChance,
              need_chance: c.weekly.needChance,
              luck_spread_mult: 1, bankruptcy_floor: c.winLose.bankruptcyBelow,
              token_reward_mult: 1, fan_rate_mult: 1)
    }
}

public struct CoevolvedWorld: Decodable {
    public struct Dealer: Decodable {
        public let params: [Double]
        public let n_params: Int
    }
    public let target_win: Double
    public let theta: Theta
    public let dealer: Dealer

    public static func load() throws -> CoevolvedWorld {
        let url = Bundle.module.url(forResource: "world_coevolved", withExtension: "json")!
        return try JSONDecoder().decode(CoevolvedWorld.self, from: Data(contentsOf: url))
    }
}

/// Empirical text-layer bonus histogram (`text_bonus_dist.json` → overall.fit):
/// a constant of the lyrics corpus, sampled — not learned.
public struct TextFitTable {
    public let values: [Double]
    public let weights: [Double]

    public static func load() throws -> TextFitTable {
        let url = Bundle.module.url(forResource: "text_bonus_dist", withExtension: "json")!
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let overall = root["overall"] as! [String: Any]
        let fit = overall["fit"] as! [String: Any]
        let pairs = fit.map { (Double($0.key)!, ($0.value as! NSNumber).doubleValue) }
            .sorted { $0.0 < $1.0 }
        return TextFitTable(values: pairs.map(\.0), weights: pairs.map(\.1))
    }

    public func sample(_ rng: inout GameRandom) -> Double {
        values[rng.weightedIndex(weights)]
    }
}
