import XCTest
@testable import ProducerKit

final class EngineTests: XCTestCase {
    static let constants = try! GameConstants.load()
    static let world = try! CoevolvedWorld.load()
    static let textFit = try! TextFitTable.load()
    var C: GameConstants { Self.constants }

    func coevolvedEngine(seed: UInt64) -> ProducerEngine {
        ProducerEngine(constants: C, world: Self.world, textFitTable: Self.textFit, seed: seed)
    }

    /// Theta with every stochastic weekly chance pinned to zero — makes the
    /// weekly transition deterministic up to jitter.
    func quietTheta() -> Theta {
        Theta(pay_mult_meme: 1, pay_mult_normal: 1, pay_mult_hit: 1, pay_mult_cult: 1,
              release_cost_mult: 1, tour_rev_mult: 1, tour_cost_mult: 1,
              salary_mult: 1, upgrade_cost_mult: 1, equip_cost_mult: 1, start_money_mult: 1,
              week_event_chance: 0, artist_event_chance: 0, need_chance: 0,
              luck_spread_mult: 1, bankruptcy_floor: -50000, token_reward_mult: 1,
              fan_rate_mult: 1)
    }

    func quietEngine(seed: UInt64 = 11) -> ProducerEngine {
        ProducerEngine(constants: C, theta: quietTheta(), dealer: nil,
                       difficulty: 0.62, textFitTable: Self.textFit, seed: seed)
    }

    func testArtist(archetype: Int = 0) -> Artist {
        Artist(name: "Тест", stats: [50, 50, 50, 50, 50, 50, 30, 50, 50],
               genre: 0, archetype: archetype, traitScore: 0, traitChaos: 0, textFit: -7)
    }

    // MARK: initial state

    func testInitialStateCoevolved() {
        let e = coevolvedEngine(seed: 1)
        XCTAssertEqual(e.money, 20000 * 0.9964, accuracy: 1e-9)
        XCTAssertEqual(e.tokens, 3)
        XCTAssertEqual(e.rep, 50)
        XCTAssertEqual(e.fans, 0)
        XCTAssertEqual(e.week, 0)
        XCTAssertEqual(e.studioLevel, 1)
        XCTAssertEqual(e.labelSlots, 2)
        XCTAssertEqual(e.candidates.count, 2)
        XCTAssertEqual(e.rosterCount, 0)
        XCTAssertTrue(e.canEndWeek)
        XCTAssertEqual(e.outcome, .running)
        for p in e.topicPop { XCTAssertTrue((5...95).contains(p)) }
        for g in e.genrePop { XCTAssertTrue((5...100).contains(g)) }
        for m in e.genreMod { XCTAssertTrue((-20...20).contains(m)) }
    }

    // MARK: sign / reject

    func testSignPutsCandidateInRosterAndRedeals() {
        let e = coevolvedEngine(seed: 2)
        let firstPair = e.candidates.map(\.id)
        XCTAssertTrue(e.sign(candidate: 0))
        XCTAssertEqual(e.rosterCount, 1)
        XCTAssertEqual(e.rejects, 0)
        XCTAssertEqual(e.candidates.count, 2)
        XCTAssertFalse(e.candidates.map(\.id).contains(firstPair[0]))
        // label tier 0 = 2 slots: third sign must fail
        XCTAssertTrue(e.sign(candidate: 0))
        XCTAssertFalse(e.canSign)
        XCTAssertFalse(e.sign(candidate: 0))
        XCTAssertEqual(e.rosterCount, 2)
    }

    func testRejectCountsBothCandidates() {
        let e = coevolvedEngine(seed: 3)
        XCTAssertTrue(e.rejectPair())
        XCTAssertEqual(e.rejects, 2)
        XCTAssertTrue(e.rejectPair())
        XCTAssertEqual(e.rejects, 4)
    }

    // MARK: release

    func testReleaseConsumesTokenAndUnlocksEndWeek() {
        let e = quietEngine()
        e.roster[0] = testArtist()
        e.weekAdvanced = true          // endWeek locked until a release
        XCTAssertFalse(e.canEndWeek)
        e.tokens = 1
        let report = e.release(slot: 0)
        XCTAssertNotNil(report)
        XCTAssertEqual(e.releases, 1)
        XCTAssertTrue(e.canEndWeek)
        XCTAssertTrue((0...4).contains(report!.tier))
        XCTAssertEqual(report!.tierName, C.tiers[report!.tier].name)
        // token: consumed 1, gained tier reward in [lo, hi]
        let range = C.tiers[report!.tier].tokenReward
        XCTAssertEqual(e.tokens, report!.tokensGained, "1 spent + gained")
        XCTAssertTrue(report!.tokensGained >= Foundation.floor(range[0]))
        XCTAssertTrue(report!.tokensGained <= range[1])
    }

    func testReleaseRequiresToken() {
        let e = quietEngine()
        e.roster[0] = testArtist()
        e.tokens = 0
        XCTAssertFalse(e.canRelease(slot: 0))
        XCTAssertNil(e.release(slot: 0))
    }

    func testReleaseReportMatchesScoreMath() {
        // deterministic cross-check: luck-free bounds. Score of the fixed
        // artist with no staff/equipment, studio 1, quiet world:
        // base = 50*(.35+.2+.1+.1+.05+.02) + 30*(-.15) = 50*0.82 - 4.5 = 36.5
        // tech = (0+0+5)*0.4 + (1*2+0)*0.3 = 2.6; textFit -7
        // genreMod contribution is clamped to ±8, luck ±8
        let e = quietEngine(seed: 123)
        e.roster[0] = testArtist()
        e.genreMod = Array(repeating: 0, count: 6)
        let report = e.release(slot: 0)!
        let deterministic = 36.5 + 2.6 - 7.0
        XCTAssertEqual(report.score, deterministic, accuracy: 8.0 + 1e-9)   // luck is the only noise
    }

    // MARK: weekly transition

    func testEndWeekAdvancesAndLocks() {
        let e = quietEngine()
        e.roster[0] = testArtist()
        XCTAssertNotNil(e.endWeek())
        XCTAssertEqual(e.week, 1)
        XCTAssertFalse(e.canEndWeek)     // locked until next release
        XCTAssertNil(e.endWeek())
        e.tokens = 5
        e.release(slot: 0)
        XCTAssertTrue(e.canEndWeek)
    }

    func testTokenStipendMinimum() {
        let e = quietEngine()
        e.roster[0] = testArtist()
        e.tokens = 0
        e.endWeek()
        XCTAssertGreaterThanOrEqual(e.tokens, 1)
    }

    func testSalariesDeductedExactly() {
        let e = quietEngine()
        e.roster[0] = testArtist()
        for i in 0..<6 { XCTAssertTrue(e.hireStaff(i)) }
        let before = e.money
        e.endWeek()
        let expected = C.staff.roles.reduce(0.0) { $0 + C.staff.salaries[$1]! }
        XCTAssertEqual(expected, 24000)
        XCTAssertEqual(e.money, before - expected, accuracy: 1e-9)
    }

    func testRehabActionAndWeeklyTick() {
        let e = quietEngine()
        var a = testArtist()
        a[stat: "addiction"] = 80
        e.roster[0] = a
        let before = e.money
        XCTAssertTrue(e.rehab(slot: 0))
        XCTAssertEqual(e.money, before - C.rehab.cost)
        XCTAssertEqual(e.roster[0]![stat: "addiction"], 50)   // 80 - 30
        XCTAssertTrue(e.roster[0]!.inRehab)
        XCTAssertEqual(e.roster[0]!.rehabWeeks, 4)
        XCTAssertFalse(e.canRehab(slot: 0))    // already in rehab
        e.endWeek()
        XCTAssertEqual(e.roster[0]!.rehabWeeks, 3)
        XCTAssertTrue(e.roster[0]!.inRehab)
        // weekly tick: -5 addiction + archetype/jitter (addiction jitter ±1)
        let arch = C.archetypeEffects[a.archetype][GameConstants.statIndex("addiction")]
        let add = e.roster[0]![stat: "addiction"]
        XCTAssertTrue(add >= 50 + arch - 5 - 1 && add <= 50 + arch - 5 + 1,
                      "addiction \(add) outside rehab-tick bounds")
        for _ in 0..<3 {
            e.weekAdvanced = false   // unlock endWeek (normally a release does)
            e.endWeek()
        }
        XCTAssertFalse(e.roster[0]!.inRehab)   // 4 weeks served
    }

    func testNeedExpiryAppliesPenalty() {
        let e = quietEngine()
        var a = testArtist()
        a.needActive = true
        a.needID = 0            // vacation: cost 10000, penalty 15
        a.needWeeks = 1
        e.roster[0] = a
        e.endWeek()
        let got = e.roster[0]!
        XCTAssertFalse(got.needActive)
        // happiness: 50 + archetype + jitter(±2) - 15
        let arch = C.archetypeEffects[a.archetype][GameConstants.statIndex("happiness")]
        let hap = got[stat: "happiness"]
        XCTAssertTrue(hap >= 50 + arch - 2 - 15 && hap <= 50 + arch + 2 - 15,
                      "happiness \(hap) missing the expiry penalty")
    }

    func testFulfillNeed() {
        let e = quietEngine()
        var a = testArtist()
        a.needActive = true
        a.needID = 3            // date: cost 8000
        a.needWeeks = 2
        e.roster[0] = a
        let before = e.money
        XCTAssertTrue(e.fulfillNeed(slot: 0))
        XCTAssertEqual(e.money, before - 8000)
        XCTAssertEqual(e.roster[0]![stat: "happiness"], 60)   // +10
        XCTAssertFalse(e.roster[0]!.needActive)
    }

    func testLowHealthConditionalHitsHappinessAndDiscipline() {
        let e = quietEngine()
        var a = testArtist(archetype: GameConstants.archetypeIDs.firstIndex(of: "romantic")!)
        a[stat: "health"] = 10
        e.roster[0] = a
        e.endWeek()
        let got = e.roster[0]!
        let archFx = C.archetypeEffects[a.archetype]
        // health stays low enough (10 + arch + jitter ±2 < 25) to trigger:
        // happiness -3, discipline -2 on top of archetype + jitter
        let hi = GameConstants.statIndex("happiness")
        let di = GameConstants.statIndex("discipline")
        XCTAssertLessThanOrEqual(got[stat: "happiness"], 50 + archFx[hi] + 2 - 3)
        XCTAssertLessThanOrEqual(got[stat: "discipline"], 50 + archFx[di] - 2)
    }

    func testStatsAlwaysClampedAfterWeeks() {
        let e = coevolvedEngine(seed: 55)
        e.sign(candidate: 0)
        e.sign(candidate: 0)
        for _ in 0..<80 {
            if e.outcome.isOver { break }
            for s in 0..<ProducerEngine.rosterSlots where e.canRelease(slot: s) {
                e.release(slot: s)
                break
            }
            e.endWeek()
            for a in e.roster.compactMap({ $0 }) {
                for v in a.stats {
                    XCTAssertGreaterThanOrEqual(v, 10)
                    XCTAssertLessThanOrEqual(v, 90)
                }
                XCTAssertTrue((0...30).contains(a.trashPop))
            }
        }
    }

    // MARK: upgrades & purchases

    func testUpgradeCostsUseThetaMultiplier() {
        let e = coevolvedEngine(seed: 6)
        e.money = 10_000_000
        XCTAssertEqual(e.studioUpgradeCost()!, 15000 * 0.8452, accuracy: 1e-9)
        XCTAssertEqual(e.labelUpgradeCost()!, 30000 * 0.8452, accuracy: 1e-9)
        XCTAssertEqual(e.equipCost(0), 2000 * 1.1351, accuracy: 1e-9)
        let m0 = e.money
        XCTAssertTrue(e.upgradeStudio())
        XCTAssertEqual(e.studioLevel, 2)
        XCTAssertEqual(e.money, m0 - 15000 * 0.8452, accuracy: 1e-6)
        XCTAssertTrue(e.upgradeLabel())
        XCTAssertEqual(e.labelSlots, 4)
        XCTAssertTrue(e.buyEquip(0))
        XCTAssertFalse(e.canBuyEquip(0))    // owned
    }

    func testStudioMaxLevelSix() {
        let e = coevolvedEngine(seed: 7)
        e.money = 100_000_000
        for _ in 0..<5 { XCTAssertTrue(e.upgradeStudio()) }
        XCTAssertEqual(e.studioLevel, 6)
        XCTAssertNil(e.studioUpgradeCost())
        XCTAssertFalse(e.canUpgradeStudio)
    }

    // MARK: win / lose

    func testBankruptcyUsesThetaFloor() {
        let e = coevolvedEngine(seed: 8)
        e.roster[0] = testArtist()
        e.money = -51000        // below vanilla -50000 but above theta floor
        e.endWeek()
        XCTAssertEqual(e.outcome, .running, "theta floor is -52214.34")
        e.weekAdvanced = false
        e.money = -53000
        e.endWeek()
        XCTAssertEqual(e.outcome, .bankrupt)
    }

    func testVictoryHasPrecedenceOverGameOver() {
        let e = coevolvedEngine(seed: 9)
        e.roster[0] = testArtist()
        e.money = -1_000_000
        e.fans = 200_000_000
        e.endWeek()
        XCTAssertEqual(e.outcome, .winFans)
    }

    func testWinYearsAt480WithRoster() {
        let e = quietEngine()
        e.roster[0] = testArtist()
        e.week = 479
        e.endWeek()
        XCTAssertEqual(e.week, 480)
        XCTAssertEqual(e.outcome, .winYears)
    }

    func testNoWinYearsWithEmptyRoster() {
        let e = quietEngine()
        e.week = 479
        e.endWeek()
        XCTAssertNotEqual(e.outcome, .winYears)
    }

    func testRejectedOutRequiresEmptyRosterAndSevenPlus() {
        let e = quietEngine()
        e.rejects = 8
        e.roster[0] = testArtist()
        e.endWeek()
        XCTAssertEqual(e.outcome, .running)     // roster non-empty
        let e2 = quietEngine(seed: 12)
        e2.rejects = 8
        e2.endWeek()
        XCTAssertEqual(e2.outcome, .rejectedOut)
        let e3 = quietEngine(seed: 13)
        e3.rejects = 6                          // strictly > 6 required
        e3.endWeek()
        XCTAssertEqual(e3.outcome, .running)
    }

    func testReputationGameOver() {
        let e = quietEngine()
        e.roster[0] = testArtist()
        e.rep = 0
        e.endWeek()
        XCTAssertEqual(e.outcome, .reputationLost)
    }

    // MARK: action cap

    func testWeeklyActionCapWithEscapeHatch() {
        let e = quietEngine()
        e.roster[0] = testArtist()
        e.tokens = 100
        e.weekActions = 16
        e.weekAdvanced = false    // endWeek open -> only endWeek allowed
        XCTAssertFalse(e.canReject)
        XCTAssertFalse(e.canTour(slot: 0))
        XCTAssertFalse(e.canRelease(slot: 0))
        XCTAssertFalse(e.canSign)
        XCTAssertTrue(e.canEndWeek)
        e.weekAdvanced = true     // endWeek locked -> release/sign escape hatch
        XCTAssertTrue(e.canRelease(slot: 0))
        XCTAssertTrue(e.canSign)
        XCTAssertFalse(e.canReject)
    }

    // MARK: trends

    func testTrendTransitionsAndClamps() {
        let e = quietEngine(seed: 21)
        e.topicPop = Array(repeating: 80, count: 10)
        e.topicDir = Array(repeating: 0, count: 10)    // rising + pop>70
        e.updateTrends()
        for d in e.topicDir { XCTAssertNotEqual(d, 0, "rising above 70 must peak") }
        e.topicPop = Array(repeating: 10, count: 10)
        e.topicDir = Array(repeating: 2, count: 10)    // falling + pop<30
        e.updateTrends()
        for d in e.topicDir { XCTAssertEqual(d, 0, "falling below 30 must rise") }
        for _ in 0..<50 {
            e.updateTrends()
            for p in e.topicPop { XCTAssertTrue((5...95).contains(p)) }
            for g in e.genrePop { XCTAssertTrue((5...100).contains(g)) }
            for m in e.genreMod { XCTAssertTrue((-20...20).contains(m)) }
        }
    }

    func testGenrePopWeeklyChangeBounded() {
        let e = quietEngine(seed: 22)
        for _ in 0..<50 {
            let before = e.genrePop
            e.updateTrends()
            for (b, a) in zip(before, e.genrePop) {
                XCTAssertLessThanOrEqual(abs(a - b), 5, "genreMaxChange is 5")
            }
        }
    }

    // MARK: bank artists (neutral world content source)

    func testBankArtistDistributions() {
        let e = quietEngine(seed: 30)
        var talentSum = 0.0, addictionSum = 0.0
        let n = 4000
        for _ in 0..<n {
            let a = e.bankArtist()
            for v in a.stats {
                XCTAssertGreaterThanOrEqual(v, 10)
                XCTAssertLessThanOrEqual(v, 90)
            }
            XCTAssertTrue((0..<6).contains(a.genre))
            XCTAssertTrue((0..<8).contains(a.archetype))
            // 1-3 distinct traits: sums bounded by 3x the extreme trait values
            let minS = C.traits.map(\.score).min()! * 3
            let maxS = C.traits.map(\.score).max()! * 3
            XCTAssertTrue((minS...maxS).contains(a.traitScore),
                          "traitScore \(a.traitScore) outside [\(minS), \(maxS)]")
            XCTAssertTrue((0...(C.traits.map(\.chaos).max()! * 3)).contains(a.traitChaos))
            talentSum += a[stat: "talent"]
            addictionSum += a[stat: "addiction"]
        }
        // talent: N(50,12) + mean genre bias (+10/6 across genres) ~ 51.7
        XCTAssertEqual(talentSum / Double(n), 51.7, accuracy: 1.5)
        // addiction: N(30,15) clamped at 10 pushes the mean up a bit
        XCTAssertEqual(addictionSum / Double(n), 31.5, accuracy: 1.5)
    }

    // MARK: dealer integration

    func testDealerFillsMemoryAndAdaptsCandidates() {
        let e = coevolvedEngine(seed: 40)
        XCTAssertEqual(e.dealerMemory.used.reduce(0, +), 2, "initial pair dealt")
        for _ in 0..<4 { e.rejectPair() }
        XCTAssertEqual(e.dealerMemory.used.reduce(0, +), 8, "ring full after 4 deals")
        for c in e.candidates {
            for v in c.stats {
                XCTAssertGreaterThanOrEqual(v, 10)
                XCTAssertLessThanOrEqual(v, 90)
            }
            XCTAssertFalse(c.name.isEmpty)
        }
    }

    // MARK: full-episode smoke (the "does the whole game hold together" test)

    /// Simple scripted policy: keep the roster full with the better candidate,
    /// release the best artist weekly, buy sound equipment when rich.
    func playEpisode(seed: UInt64) -> ProducerEngine {
        let e = coevolvedEngine(seed: seed)
        while !e.outcome.isOver {
            if e.canSign {
                let best = e.candidates[0][stat: "talent"] >= e.candidates[1][stat: "talent"] ? 0 : 1
                e.sign(candidate: best)
            }
            let slots = (0..<ProducerEngine.rosterSlots).filter { e.canRelease(slot: $0) }
            if let s = slots.max(by: { e.roster[$0]![stat: "talent"] < e.roster[$1]![stat: "talent"] }) {
                e.release(slot: s)
            }
            for s in 0..<ProducerEngine.rosterSlots where e.canFulfillNeed(slot: s) && e.money > 60000 {
                e.fulfillNeed(slot: s)
            }
            if e.money > 150_000, let i = e.equipOwned.firstIndex(of: false), e.canBuyEquip(i) {
                e.buyEquip(i)
            }
            if e.canEndWeek {
                e.endWeek()
            } else if e.rosterCount == 0 || e.tokens < 1 {
                break   // cannot release, cannot end week: dead position guard
            }
            XCTAssertTrue(e.money.isFinite)
            XCTAssertGreaterThanOrEqual(e.fans, 0)
            if e.week > ProducerEngine.maxWeeks { break }
        }
        return e
    }

    /// Coevolved world under a crude script: the calibration target (62%)
    /// belongs to the trained PPO player, not this policy — the smoke test
    /// asserts the game holds together, not a win rate.
    func testFullEpisodesTerminateWithInvariantsIntact() {
        var weeks: [Int] = []
        for seed in 0..<30 {
            let e = playEpisode(seed: UInt64(seed) * 7919 + 1)
            XCTAssertTrue(e.outcome.isOver, "episode \(seed) did not terminate (week \(e.week))")
            XCTAssertLessThanOrEqual(e.week, ProducerEngine.maxWeeks)
            XCTAssertTrue(e.money.isFinite)
            XCTAssertGreaterThanOrEqual(e.fans, 0)
            XCTAssertTrue((0...100).contains(e.rep))
            weeks.append(e.week)
        }
        // outcomes must be decided by play, not instant (v0 bug: dead in <=8)
        XCTAssertGreaterThan(weeks.sorted()[15], 8,
                             "median survival should exceed the broken-v0 signature")
    }

    func testEpisodeIsDeterministicForSameSeed() {
        let a = playEpisode(seed: 424242)
        let b = playEpisode(seed: 424242)
        XCTAssertEqual(a.outcome, b.outcome)
        XCTAssertEqual(a.week, b.week)
        XCTAssertEqual(a.money, b.money)
        XCTAssertEqual(a.fans, b.fans)
        XCTAssertEqual(a.releases, b.releases)
    }
}
