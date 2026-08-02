import XCTest
@testable import ProducerKit

/// Golden-value parity tests. Every golden below was computed with float64
/// Python directly from the shipped artifacts (game_constants.json,
/// world_coevolved.json) using the formulas in torchsim/env_producer.py —
/// the sim that holds 102/102 statistical parity vs the TypeScript game.
final class MathParityTests: XCTestCase {
    static let constants = try! GameConstants.load()
    static let world = try! CoevolvedWorld.load()
    var C: GameConstants { Self.constants }
    var theta: Theta { Self.world.theta }

    // canonical inputs shared by the score/tour goldens
    // stats order: talent, discipline, charisma, health, happiness,
    //              popularity, addiction, reputation, selfConfidence
    let stats: [Double] = [60, 50, 70, 55, 45, 40, 20, 50, 65]

    func allStaff() -> ReleaseMath.StaffEffects {
        .init(hired: [true, true, true, true, true, true],
              roles: C.staff.roles, bonuses: C.staff.bonuses)
    }

    func noStaff() -> ReleaseMath.StaffEffects {
        .init(hired: Array(repeating: false, count: 6),
              roles: C.staff.roles, bonuses: C.staff.bonuses)
    }

    // MARK: release score

    func testReleaseScoreGolden() {
        let score = ReleaseMath.score(
            stats: stats, sf: C.scoreFormula, equipBonus: 10, staff: allStaff(),
            prodLevel: 3, studioLevel: 2, studioQuality: C.studioUpgrades[1].qualityBonus,
            genreMod: 5, trashPop: 4, traitScore: 3.5, traitChaos: 2.0, textFit: -7,
            luck: 4 * theta.luck_spread_mult)
        XCTAssertEqual(score, 63.17520000000002, accuracy: 1e-9)
    }

    func testScoreClampAndTrendFreakClamps() {
        // huge inputs pin the clamps: trend at ±8, freak at 9, score at 160
        let hi = ReleaseMath.score(
            stats: [90, 90, 90, 90, 90, 90, 10, 90, 90], sf: C.scoreFormula,
            equipBonus: 100, staff: allStaff(), prodLevel: 20, studioLevel: 6,
            studioQuality: 25, genreMod: 100, trashPop: 100, traitScore: 21,
            traitChaos: 10, textFit: 10, luck: 8)
        XCTAssertEqual(hi, 160)
        let lo = ReleaseMath.score(
            stats: [10, 10, 10, 10, 10, 10, 90, 10, 10], sf: C.scoreFormula,
            equipBonus: 0, staff: noStaff(), prodLevel: 1, studioLevel: 1,
            studioQuality: 0, genreMod: -100, trashPop: 0, traitScore: -15,
            traitChaos: 0, textFit: -10, luck: -8)
        XCTAssertEqual(lo, 0)   // deeply negative raw score clamps to 0
    }

    func testTierBoundariesBelongToHigherTier() {
        let t = C.scoreFormula.tierThresholds   // [25, 50, 75, 100]
        XCTAssertEqual(ReleaseMath.tier(score: 0, thresholds: t), 0)
        XCTAssertEqual(ReleaseMath.tier(score: 24.999, thresholds: t), 0)
        XCTAssertEqual(ReleaseMath.tier(score: 25, thresholds: t), 1)
        XCTAssertEqual(ReleaseMath.tier(score: 49.9, thresholds: t), 1)
        XCTAssertEqual(ReleaseMath.tier(score: 50, thresholds: t), 2)
        XCTAssertEqual(ReleaseMath.tier(score: 75, thresholds: t), 3)
        XCTAssertEqual(ReleaseMath.tier(score: 100, thresholds: t), 4)
        XCTAssertEqual(ReleaseMath.tier(score: 160, thresholds: t), 4)
    }

    // MARK: release economics

    func testEconomicsGoldenHitTier() {
        // tier 3 (Хіт), all staff: lawyer +6% profit, accountant -5% cost
        let eco = ReleaseMath.economics(
            listeners: 1_000_000, fanRateRoll: 0.05, payRateRoll: 0.02,
            costRoll: 12000, tokenRoll: 4, tierPayMult: theta.payMult[3],
            theta: theta, staff: allStaff())
        XCTAssertEqual(eco.fansGained, 34470)
        XCTAssertEqual(eco.moneyDelta, 7985)
        XCTAssertEqual(eco.tokensGained, 3)
    }

    func testTokenRewardMultIsSelfLimiting() {
        // the anti-release-machine-gun knob: floor(1 * 0.8084) == 0 tokens —
        // a Провал/low roll no longer refunds the token it consumed
        let eco = ReleaseMath.economics(
            listeners: 100, fanRateRoll: 0, payRateRoll: 0.001, costRoll: 3000,
            tokenRoll: 1, tierPayMult: 1.0, theta: theta, staff: noStaff())
        XCTAssertEqual(eco.tokensGained, 0)
        XCTAssertLessThan(theta.token_reward_mult, 1.0)
    }

    func testProvalTierPayMultUntouchedByTheta() {
        XCTAssertEqual(theta.payMult[0], 1.0)
        XCTAssertEqual(theta.payMult[4], theta.pay_mult_cult)
    }

    func testPopBoost() {
        let pb = C.scoreFormula.popBoost
        XCTAssertEqual(ReleaseMath.popBoost(score: 40, pb: pb), 0)
        XCTAssertEqual(ReleaseMath.popBoost(score: 47, pb: pb), 1)   // round(1.4)
        XCTAssertEqual(ReleaseMath.popBoost(score: 160, pb: pb), 10) // clamp hi
        XCTAssertEqual(ReleaseMath.popBoost(score: 0, pb: pb), -3)   // clamp lo
    }

    func testProducerXPLevelUps() {
        let sf = C.scoreFormula
        var r = ReleaseMath.applyXP(xp: 0, level: 1, xpNext: 100, gain: 100, sf: sf)
        XCTAssertEqual(r.level, 2)
        XCTAssertEqual(r.xp, 0)
        XCTAssertEqual(r.xpNext, 150)
        // 475 = 100 + 150 + 225 exactly -> triple level-up in one release
        r = ReleaseMath.applyXP(xp: 0, level: 1, xpNext: 100, gain: 475, sf: sf)
        XCTAssertEqual(r.level, 4)
        XCTAssertEqual(r.xp, 0)
        XCTAssertEqual(r.xpNext, 338)   // tsRound(225 * 1.5) = tsRound(337.5)
    }

    // MARK: tour

    func testTourTotalGoldenWithHealthPenalty() {
        // popularity 60, health 30 (penalty (40-30)*0.25 = 2.5), gmod 5,
        // manager hired (5*0.5 = 2.5), luck +5
        var s = stats
        s[GameConstants.statIndex("popularity")] = 60
        s[GameConstants.statIndex("health")] = 30
        let total = TourMath.total(stats: s, tour: C.tour, genreMod: 5,
                                   managerEffect: 2.5, luck: 5)
        XCTAssertEqual(total, 37.375, accuracy: 1e-12)
    }

    func testTourSuccessThresholdBoundary() {
        let r = TourMath.outcome(total: 40, popularity: 50, tour: C.tour, theta: theta,
                                 revNoise: 0, failFanRoll: 0)
        XCTAssertTrue(r.success)    // total == threshold succeeds (>= check)
        let f = TourMath.outcome(total: 39.999, popularity: 50, tour: C.tour, theta: theta,
                                 revNoise: 0, failFanRoll: 123)
        XCTAssertFalse(f.success)
        XCTAssertEqual(f.fansGained, 123)
    }

    func testTourEconomicsGoldens() {
        // fail branch: pop 60, noise +3000 -> clamp(18000+3000, 0, 50000) = 21000
        let fail = TourMath.outcome(total: 37.375, popularity: 60, tour: C.tour,
                                    theta: theta, revNoise: 3000, failFanRoll: 500)
        XCTAssertEqual(fail.revenue, 21000 * theta.tour_rev_mult, accuracy: 1e-9)
        XCTAssertEqual(fail.cost, 45000 * theta.tour_cost_mult, accuracy: 1e-9)
        // success branch: pop 60, total 80 -> rev clamps at 500k, fans 34000
        let ok = TourMath.outcome(total: 80, popularity: 60, tour: C.tour,
                                  theta: theta, revNoise: 3000, failFanRoll: 0)
        XCTAssertEqual(ok.revenue, 500_000 * theta.tour_rev_mult, accuracy: 1e-9)
        XCTAssertEqual(ok.fansGained, 34000)
    }

    func testTourNoHealthPenaltyAtOrAbove40() {
        var s = stats
        s[GameConstants.statIndex("health")] = 40
        let at40 = TourMath.total(stats: s, tour: C.tour, genreMod: 0, managerEffect: 0, luck: 0)
        s[GameConstants.statIndex("health")] = 90
        let at90 = TourMath.total(stats: s, tour: C.tour, genreMod: 0, managerEffect: 0, luck: 0)
        XCTAssertEqual(at40, at90)  // health only matters below 40
    }

    // MARK: tsRound semantics

    func testTSRoundHalfUp() {
        XCTAssertEqual(tsRound(1.5), 2)
        XCTAssertEqual(tsRound(-1.5), -1)   // JS Math.round(-1.5) == -1
        XCTAssertEqual(tsRound(-2.5), -2)
        XCTAssertEqual(tsRound(2.4), 2)
        XCTAssertEqual(tsRound(-2.6), -3)
    }
}
