import Foundation

/// Pure release math (rule-parity with torchsim `env_producer._release`,
/// itself statistically validated against the TS game). All randomness is
/// passed in as explicit rolls so every formula is unit-testable.
public enum ReleaseMath {

    public struct StaffEffects {
        public let soundEngineer, pr, lawyer, accountant, manager, security: Double

        /// From hire flags + the bonuses table (torchsim staff coefficients).
        public init(hired: [Bool], roles: [String], bonuses: [String: Double]) {
            func bonus(_ role: String) -> Double {
                guard let i = roles.firstIndex(of: role), hired[i] else { return 0 }
                return bonuses[role] ?? 0
            }
            soundEngineer = bonus("soundEngineer")
            pr = bonus("pr")
            lawyer = bonus("lawyer") * 0.01
            accountant = bonus("accountant") * 0.01
            manager = bonus("manager") * 0.5
            security = bonus("security") * 0.3
        }
    }

    /// The release score before clamping to tiers. `luck` is the already
    /// theta-scaled roll: randInt(luck lo, hi) * luck_spread_mult.
    public static func score(stats: [Double], sf: GameConstants.ScoreFormula,
                             equipBonus: Double, staff: StaffEffects,
                             prodLevel: Double, studioLevel: Double, studioQuality: Double,
                             genreMod: Double, trashPop: Double,
                             traitScore: Double, traitChaos: Double, textFit: Double,
                             luck: Double) -> Double {
        var base = 0.0
        for (stat, w) in sf.weights {
            base += stats[GameConstants.statIndex(stat)] * w
        }
        let levelMult = 1 + (prodLevel - 1) * 0.1
        let producerBonus = tsRound(5 * levelMult)   // 'talented' specialization
        let tech = (equipBonus + staff.soundEngineer + producerBonus) * sf.techEquipStaffProducerMult
            + (studioLevel * sf.studioLevelCoef + studioQuality) * sf.studioMult
        let managerB = staff.manager * sf.managerMult
        let prB = staff.pr * sf.prMult
        let chaosMult = max(1 - staff.security * 0.15, 0.1)
        let trendB = clamp(genreMod * sf.trendMult, -sf.trendClamp, sf.trendClamp)
        let freakB = clamp(trashPop * sf.freakMult, 0, sf.freakClamp)
        let total = base + tech + managerB + prB + trendB + freakB
            + traitScore + traitChaos * chaosMult * sf.chaosMult + luck + textFit
        return clamp(total, sf.scoreClamp[0], sf.scoreClamp[1])
    }

    /// Tier from score. Boundary belongs to the HIGHER tier (TS `<` checks;
    /// torch bucketize right=True): score == 25 is already "Локальний мем".
    public static func tier(score: Double, thresholds: [Double]) -> Int {
        thresholds.filter { score >= $0 }.count
    }

    public struct Economics {
        public let fansGained: Double
        public let moneyDelta: Double
        public let tokensGained: Double
    }

    /// Economics from raw tier rolls. `listeners`/`costRoll`/`tokenRoll` are
    /// randInt draws in the tier's ranges, `fanRateRoll`/`payRateRoll` uniform
    /// draws in the tier's ranges.
    public static func economics(listeners: Double, fanRateRoll: Double, payRateRoll: Double,
                                 costRoll: Double, tokenRoll: Double,
                                 tierPayMult: Double, theta: Theta,
                                 staff: StaffEffects) -> Economics {
        let fans = tsRound(listeners * fanRateRoll * theta.fan_rate_mult)
        let revenue = listeners * payRateRoll * tierPayMult
        let profitMult = 1.0 * (1 + staff.lawyer)       // 'talented': no profit bonus
        let cost = costRoll * theta.release_cost_mult
        let adjCost = tsRound(cost * (1 - staff.accountant))
        let money = tsRound(revenue * profitMult - adjCost)
        let tokens = Foundation.floor(tokenRoll * theta.token_reward_mult)
        return Economics(fansGained: fans, moneyDelta: money, tokensGained: tokens)
    }

    /// Post-release popularity boost: round((score-40)/5) clamped to [-3, 10].
    public static func popBoost(score: Double, pb: GameConstants.PopBoost) -> Double {
        clamp(tsRound((score - pb.sub) / pb.div), pb.clamp[0], pb.clamp[1])
    }

    /// Producer XP level-ups; returns updated (xp, level, xpNext).
    public static func applyXP(xp: Double, level: Double, xpNext: Double,
                               gain: Double, sf: GameConstants.ScoreFormula)
        -> (xp: Double, level: Double, xpNext: Double) {
        var (x, l, nxt) = (xp + gain, level, xpNext)
        for _ in 0..<3 where x >= nxt {
            x -= nxt
            l += 1
            nxt = tsRound(nxt * sf.expToNextMult)
        }
        return (x, l, nxt)
    }
}
