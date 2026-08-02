import Foundation

/// Pure tour math (parity with torchsim `env_producer._tour`).
public enum TourMath {

    /// Tour quality total in [0, 100]; `luck` is randInt(luck lo, hi).
    public static func total(stats: [Double], tour: GameConstants.Tour,
                             genreMod: Double, managerEffect: Double,
                             luck: Double) -> Double {
        let w = tour.weights
        let pop = stats[GameConstants.statIndex("popularity")]
        let base = pop * w["popularity"]!
            + stats[GameConstants.statIndex("charisma")] * w["charisma"]!
            + stats[GameConstants.statIndex("reputation")] * w["reputation"]!
            + genreMod * w["trend"]!
            + managerEffect * w["manager"]!
        let health = stats[GameConstants.statIndex("health")]
        let penalty = health < tour.healthPenaltyBelow
            ? (tour.healthPenaltyBelow - health) * tour.healthPenaltyMult : 0
        return clamp(base + luck - penalty, 0, 100)
    }

    public struct Result {
        public let success: Bool
        public let revenue: Double     // theta-scaled gross revenue
        public let cost: Double        // theta-scaled cost
        public let fansGained: Double
        public var moneyDelta: Double { revenue - cost }
    }

    /// `revNoise`/`fanRoll` are the raw randInt draws for the taken branch
    /// (success: revNoise in success.revNoise; fail: revNoise in fail.revNoise
    /// and fanRoll = randInt(fansMin, max(fansMin, round(pop*fansPerPopMax)))).
    public static func outcome(total: Double, popularity pop: Double,
                               tour: GameConstants.Tour, theta: Theta,
                               revNoise: Double, failFanRoll: Double) -> Result {
        let success = total >= tour.successThreshold
        let revenue: Double
        let fans: Double
        if success {
            let s = tour.success
            revenue = clamp(tsRound(pop * s.revPerPop + total * s.revPerTotal + revNoise),
                            s.revClamp[0], s.revClamp[1])
            fans = tsRound(clamp(pop * s.fansPerPop + total * s.fansPerTotal,
                                 s.fansClamp[0], s.fansClamp[1]))
        } else {
            let f = tour.fail
            revenue = clamp(pop * f.revPerPop + revNoise, f.revClamp[0], f.revClamp[1])
            fans = failFanRoll
        }
        let cost = (tour.costBase + tsRound(pop * tour.costPerPop)) * theta.tour_cost_mult
        return Result(success: success, revenue: revenue * theta.tour_rev_mult,
                      cost: cost, fansGained: fans)
    }

    public static func cost(popularity pop: Double, tour: GameConstants.Tour,
                            theta: Theta) -> Double {
        (tour.costBase + tsRound(pop * tour.costPerPop)) * theta.tour_cost_mult
    }
}
