import Foundation

/// Single source of truth: `game_constants.json`, exported from the TypeScript
/// game (torchsim anti-drift rule — no gameplay literal lives in engine code).
public struct GameConstants: Decodable {
    // Canonical channel orders (match torchsim world_config.py; the JSON's
    // dict key order is not something JSONDecoder preserves, so the two
    // index-sensitive orders are pinned here and asserted in tests).
    public static let stats = ["talent", "discipline", "charisma", "health", "happiness",
                               "popularity", "addiction", "reputation", "selfConfidence"]
    public static let archetypeIDs = ["punk", "workaholic", "alcoholic", "romantic",
                                      "lazy", "genius", "diva", "street"]
    public static func statIndex(_ name: String) -> Int { stats.firstIndex(of: name)! }

    public struct Start: Decodable {
        public let money, fans, tokens, reputation: Double
        public let studioLevel: Int
        public let labelSlotIndex: Int
    }

    public struct PopBoost: Decodable {
        public let div, sub: Double
        public let clamp: [Double]
    }

    public struct ScoreFormula: Decodable {
        public let weights: [String: Double]
        public let techEquipStaffProducerMult, studioMult, studioLevelCoef: Double
        public let managerMult, prMult, securityEffectMult: Double
        public let trendMult, trendClamp, freakMult, freakClamp, chaosMult: Double
        public let luck: [Double]
        public let scoreClamp: [Double]
        public let tierThresholds: [Double]
        public let popBoost: PopBoost
        public let expGain: [Double]
        public let repChange: [Double]
        public let expToNextMult, expToNextBase: Double
    }

    public struct Tier: Decodable {
        public let name: String
        public let listeners, fanRate, payRate, cost, tokenReward: [Double]
    }

    public struct TourSuccess: Decodable {
        public let revPerPop, revPerTotal: Double
        public let revNoise, revClamp: [Double]
        public let fansPerPop, fansPerTotal: Double
        public let fansClamp: [Double]
    }

    public struct TourFail: Decodable {
        public let revPerPop: Double
        public let revNoise, revClamp: [Double]
        public let fansMin, fansPerPopMax: Double
    }

    public struct TourOnSuccess: Decodable {
        public let popGain: [Double]
        public let happinessGain: Double
    }

    public struct TourOnFail: Decodable {
        public let popLoss: [Double]
        public let happinessLoss, healthLoss: Double
    }

    public struct Tour: Decodable {
        public let costBase, costPerPop: Double
        public let weights: [String: Double]
        public let healthPenaltyBelow, healthPenaltyMult: Double
        public let luck: [Double]
        public let successThreshold: Double
        public let fail: TourFail
        public let success: TourSuccess
        public let onSuccess: TourOnSuccess
        public let onFail: TourOnFail
        public let cooldownWeeks: Int
    }

    public struct Rehab: Decodable {
        public let cost: Double
        public let weeks: Int
        public let addictionDrop, weeklyHealthGain, weeklyAddictionDrop: Double
    }

    public struct ArtistGen: Decodable {
        public let statNorm: [String: [Double]]
        public let clamp: [Double]
        public let genreBias: [String: [String: Double]]
        public let traitsCount: [Int]
    }

    public struct ThresholdEffect: Decodable {
        public let below: Double?
        public let above: Double?
        public let discipline: Double?
        public let happiness: Double?
        public let health: Double?
    }

    public struct FreakEmergence: Decodable {
        public let selfConfidenceAbove, talentBelow, chance: Double
        public let trashPopGain, trashPopClamp, popGain: [Double]
    }

    public struct Weekly: Decodable {
        public let jitter: [String: [Double]]
        public let lowHappiness, lowHealth, highAddiction: ThresholdEffect
        public let freakEmergence: FreakEmergence
        public let needChance, needInnerChance: Double
        public let needWeeks: Int
        public let artistEventChance, weekEventChance, tokenStipendMin: Double
        public let statClamp: [Double]
    }

    public struct WinLose: Decodable {
        public let bankruptcyBelow: Double
        public let rejectsForGameOver: Double
        public let repGameOverAt: Double
        public let fansForVictory: Double
        public let yearsForVictory: Double
    }

    public struct Trends: Decodable {
        public let topics: [String]
        public let genreAffinity: [String: [String]]
        public let genreDrift: [String: Double]
        public let topicDrift, topicClamp, genreStep: [Double]
        public let genreDriftMult, genreJumpChance: Double
        public let genreJump: [Double]
        public let genreMaxChange: Double
        public let genreClamp: [Double]
        public let modMult: Double
        public let modNoise, modClamp: [Double]
        public let initTopicPop: [Double]
    }

    public struct ArtistEvent: Decodable {
        public let w: Double
        public let add, hap: [Double]
        public let fx: [String: [Double]]
    }

    public struct StudioUpgrade: Decodable {
        public let level: Int
        public let qualityBonus, cost: Double
    }

    public struct LabelSlot: Decodable {
        public let slots: Int
        public let cost: Double
    }

    public struct Equipment: Decodable {
        public let id: String
        public let cost, bonus: Double
    }

    public struct Need: Decodable {
        public let id: String
        public let cost, happinessPenalty: Double
    }

    public struct WeekEvent: Decodable {
        public let money, fans, rep, tokens: Double
    }

    public struct Trait: Decodable {
        public let score, chaos: Double
    }

    public struct Staff: Decodable {
        public let roles: [String]
        public let salaries: [String: Double]
        public let bonuses: [String: Double]
    }

    public let start: Start
    public let scoreFormula: ScoreFormula
    public let tiers: [Tier]
    public let tour: Tour
    public let rehab: Rehab
    public let artistGen: ArtistGen
    public let weekly: Weekly
    public let winLose: WinLose
    public let trends: Trends
    public let artistEvents: [ArtistEvent]
    public let studioUpgrades: [StudioUpgrade]
    public let labelSlots: [LabelSlot]
    public let equipment: [Equipment]
    public let needs: [Need]
    public let needFulfillHappiness: Double
    public let weekEvents: [WeekEvent]
    public let traits: [Trait]
    public let archetypes: [String: [String: Double]]
    public let genres: [String]
    public let staff: Staff

    /// Archetype weekly stat deltas indexed [archetype][stat] in canonical order.
    public var archetypeEffects: [[Double]] {
        Self.archetypeIDs.map { aid in
            GameConstants.stats.map { archetypes[aid]?[$0] ?? 0 }
        }
    }

    public static func load() throws -> GameConstants {
        let url = Bundle.module.url(forResource: "game_constants", withExtension: "json")!
        return try JSONDecoder().decode(GameConstants.self, from: Data(contentsOf: url))
    }
}
