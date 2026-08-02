import XCTest
@testable import ProducerKit

/// Statistical gate parity: Swift mirrors of the scripted gate policies
/// (torchsim/py_policies.py, themselves mirrors of scripts/policies.ts) run
/// on the NEUTRAL world (default theta, i.i.d. bank artists) — the same
/// configuration as the golden gate runs against the real TS game:
///   greedy-heuristic: win-fans 0.686, bankrupt 0.312 (n=1000, median 63 wk)
///   sign-release-spam: bankrupt 0.775, reputation 0.142, win-years 0.083
///   random-legal:      bankrupt 1.000 (median 6 wk)
/// RNG streams differ, so we assert rate bands (binomial ±5σ for n=300).
final class GateParityTests: XCTestCase {
    static let constants = try! GameConstants.load()
    static let textFit = try! TextFitTable.load()
    var C: GameConstants { Self.constants }

    func neutralEngine(seed: UInt64) -> ProducerEngine {
        ProducerEngine(constants: C, theta: .neutral(C), dealer: nil,
                       difficulty: 0.62, textFitTable: Self.textFit, seed: seed)
    }

    /// headless expectedScore: stat-weighted sum + traitScore (no clamps).
    func expectedScore(_ a: Artist) -> Double {
        let w = C.scoreFormula.weights
        return w.reduce(0.0) { $0 + a[stat: $1.key] * $1.value } + a.traitScore
    }

    // MARK: greedy-heuristic mirror (py_policies.greedy_heuristic priorities)

    /// The TS gate driver (mirrored in test_parity.run_env_policy) lets the
    /// scripted policies release each artist at most ONCE per week, with an
    /// escape hatch when endWeek is locked and everyone was already released.
    /// The env itself allows re-releases (that freedom is the RL exploit the
    /// coevolved token_reward_mult neutralizes) — so the tracker lives in the
    /// policy, not in the engine.
    func greedyStep(_ e: ProducerEngine, weekRejects: inout Int,
                    released: inout [Bool]) -> Bool {
        // returns false when the week ended (or nothing possible)
        let alive = (0..<ProducerEngine.rosterSlots).filter { e.roster[$0] != nil }
        let exp = e.roster.map { $0.map(expectedScore) ?? -Double.infinity }
        let budgetOK = e.weekActions < ProducerEngine.maxActionsPerWeek - 4

        // 1. sign best candidate / reject
        if budgetOK, e.canSign {
            let e0 = expectedScore(e.candidates[0])
            let e1 = expectedScore(e.candidates[1])
            let best = e0 >= e1 ? 0 : 1
            let aliveExp = alive.map { exp[$0] }.sorted()
            let med = aliveExp.isEmpty ? -1e9 : aliveExp[min(alive.count / 2, aliveExp.count - 1)]
            let cap = Double(e.labelSlots)
            if alive.isEmpty || Double(alive.count) < cap / 2 || max(e0, e1) > med {
                return e.sign(candidate: best)
            }
            if weekRejects < 2, alive.count < e.labelSlots, e.canReject {
                weekRejects += 1
                return e.rejectPair()
            }
        }
        // 2. cheap needs
        for s in alive {
            if let a = e.roster[s], a.needActive,
               C.needs[a.needID].cost < 10000, e.money > 30000, e.canFulfillNeed(slot: s) {
                return e.fulfillNeed(slot: s)
            }
        }
        // 3. rehab
        for s in alive {
            if let a = e.roster[s], a[stat: "addiction"] > 65, !a.inRehab,
               e.money > 60000, e.canRehab(slot: s) {
                return e.rehab(slot: s)
            }
        }
        // 4. tours by base score
        if e.weekActions < ProducerEngine.maxActionsPerWeek - 2 {
            let tourable = alive.compactMap { s -> (Int, Double)? in
                guard let a = e.roster[s] else { return nil }
                let tb = a[stat: "popularity"] * 0.3 + a[stat: "charisma"] * 0.15
                    + a[stat: "reputation"] * 0.1
                let cost = 15000 + tsRound(a[stat: "popularity"] * 500)
                guard tb >= 37, a[stat: "health"] >= 45, !a.inRehab, a.tourCooldown <= 0,
                      e.money >= cost + 10000, e.canTour(slot: s) else { return nil }
                return (s, tb)
            }
            if let best = tourable.max(by: { $0.1 < $1.1 }) {
                return e.tour(slot: best.0) != nil
            }
        }
        // 5-7. purchases only before the week's first release
        if !released.contains(true) {
            let hires: [(String, Bool)] = [
                ("soundEngineer", e.week >= 4 && e.money > 50000),
                ("pr", e.week >= 4 && e.money > 50000),
                ("manager", e.money > 150_000), ("accountant", e.money > 150_000),
                ("lawyer", e.money > 150_000), ("security", e.money > 200_000)]
            for (role, cond) in hires where cond {
                let r = C.staff.roles.firstIndex(of: role)!
                if e.canHireStaff(r) { return e.hireStaff(r) }
            }
            if e.money < 0 {
                for r in 0..<C.staff.roles.count where e.canFireStaff(r) {
                    return e.fireStaff(r)
                }
            }
            let buyable = (0..<C.equipment.count).filter {
                !e.equipOwned[$0] && e.money > C.equipment[$0].cost * 3 && e.canBuyEquip($0)
            }
            if let best = buyable.max(by: {
                C.equipment[$0].bonus / C.equipment[$0].cost < C.equipment[$1].bonus / C.equipment[$1].cost
            }) {
                return e.buyEquip(best)
            }
            if alive.count >= e.labelSlots, let cost = e.labelUpgradeCost(),
               e.money > cost / e.theta.upgrade_cost_mult * 2, e.canUpgradeLabel {
                return e.upgradeLabel()
            }
            if let cost = e.studioUpgradeCost(),
               e.money > cost / e.theta.upgrade_cost_mult * 2, e.canUpgradeStudio {
                return e.upgradeStudio()
            }
        }
        // 8. release best unreleased exp >= 30; escape hatch when endWeek locked
        let releasable = alive.filter { e.canRelease(slot: $0) && !released[$0] }
        let good = releasable.filter { exp[$0] >= 30 }
        if let s = good.max(by: { exp[$0] < exp[$1] }) {
            released[s] = true
            return e.release(slot: s) != nil
        }
        if !e.canEndWeek {
            let any = releasable.isEmpty
                ? alive.filter { e.canRelease(slot: $0) } : releasable
            if let s = any.max(by: { exp[$0] < exp[$1] }) {
                released[s] = true
                return e.release(slot: s) != nil
            }
        }
        return false
    }

    func playGreedy(seed: UInt64) -> ProducerEngine {
        let e = neutralEngine(seed: seed)
        while !e.outcome.isOver {
            var weekRejects = 0
            var released = [Bool](repeating: false, count: ProducerEngine.rosterSlots)
            var guardCount = 0
            while greedyStep(e, weekRejects: &weekRejects, released: &released) {
                guardCount += 1
                if guardCount > 64 || e.outcome.isOver { break }
            }
            if e.outcome.isOver { break }
            if e.canEndWeek {
                e.endWeek()
            } else {
                break   // endWeek locked and no legal release: dead position
            }
        }
        return e
    }

    func testGreedyHeuristicMatchesGateRates() {
        var outcomes: [GameOutcome] = []
        var weeks: [Int] = []
        let n = 300
        for i in 0..<n {
            let e = playGreedy(seed: UInt64(i) &* 2_654_435_761 &+ 17)
            XCTAssertTrue(e.outcome.isOver, "episode \(i) stuck at week \(e.week)")
            outcomes.append(e.outcome)
            weeks.append(e.week)
        }
        let winFans = Double(outcomes.filter { $0 == .winFans }.count) / Double(n)
        let bankrupt = Double(outcomes.filter { $0 == .bankrupt }.count) / Double(n)
        // gate golden: 0.686 win-fans / 0.312 bankrupt. ±5σ(n=300) ≈ ±0.135
        XCTAssertEqual(winFans, 0.686, accuracy: 0.15,
                       "greedy win-fans rate drifted from the TS gate")
        XCTAssertEqual(bankrupt, 0.312, accuracy: 0.15,
                       "greedy bankruptcy rate drifted from the TS gate")
        let medianWeeks = weeks.sorted()[n / 2]
        XCTAssertEqual(Double(medianWeeks), 63, accuracy: 25,
                       "greedy median episode length drifted (gate: 63 weeks)")
    }

    // MARK: sign-release-spam mirror

    func playSpam(seed: UInt64) -> ProducerEngine {
        let e = neutralEngine(seed: seed)
        while !e.outcome.isOver {
            var released = [Bool](repeating: false, count: ProducerEngine.rosterSlots)
            var guardCount = 0
            weekLoop: while !e.outcome.isOver {
                guardCount += 1
                if guardCount > 64 { break }
                if e.canSign {
                    e.sign(candidate: 0)
                } else if let s = (0..<ProducerEngine.rosterSlots)
                    .first(where: { e.canRelease(slot: $0) && !released[$0] }) {
                    released[s] = true
                    e.release(slot: s)
                } else if !e.canEndWeek,
                          let s = (0..<ProducerEngine.rosterSlots).first(where: { e.canRelease(slot: $0) }) {
                    released[s] = true   // escape hatch: re-release to unlock endWeek
                    e.release(slot: s)
                } else {
                    break weekLoop
                }
            }
            if e.outcome.isOver { break }
            if e.canEndWeek { e.endWeek() } else { break }
        }
        return e
    }

    func testSignReleaseSpamGoesBrokeLikeTheGate() {
        var outcomes: [GameOutcome] = []
        let n = 200
        for i in 0..<n {
            let e = playSpam(seed: UInt64(i) &* 40_503 &+ 3)
            XCTAssertTrue(e.outcome.isOver)
            outcomes.append(e.outcome)
        }
        let bankrupt = Double(outcomes.filter { $0 == .bankrupt }.count) / Double(n)
        // gate golden: 0.775 bankrupt (rest reputation-death / win-years)
        XCTAssertEqual(bankrupt, 0.775, accuracy: 0.15,
                       "spam bankruptcy rate drifted from the TS gate")
        XCTAssertEqual(outcomes.filter { $0 == .winFans }.count, 0,
                       "spam must never fan-snowball")
    }

    // MARK: random-legal (blind play must lose fast — the decisions-matter gate)

    func playRandomLegal(seed: UInt64) -> ProducerEngine {
        let e = neutralEngine(seed: seed)
        var rng = GameRandom(seed: seed &+ 999)
        while !e.outcome.isOver {
            var acting = true
            var guardCount = 0
            while acting && !e.outcome.isOver {
                guardCount += 1
                if guardCount > 64 { break }
                if rng.chance(0.25) { acting = false; break }
                // uniform pick over the legal thunk families
                var thunks: [() -> Void] = []
                if e.canSign { thunks.append { e.sign(candidate: 0) }; thunks.append { e.sign(candidate: 1) } }
                if e.canReject { thunks.append { e.rejectPair() } }
                for s in 0..<ProducerEngine.rosterSlots {
                    if e.canRelease(slot: s) { thunks.append { e.release(slot: s) } }
                    if e.canTour(slot: s) { thunks.append { e.tour(slot: s) } }
                    if e.canRehab(slot: s) { thunks.append { e.rehab(slot: s) } }
                    if e.canFire(slot: s) { thunks.append { e.fire(slot: s) } }
                    if e.canFulfillNeed(slot: s) { thunks.append { e.fulfillNeed(slot: s) } }
                }
                for r in 0..<6 {
                    if e.canHireStaff(r) { thunks.append { e.hireStaff(r) } }
                    if e.canFireStaff(r) { thunks.append { e.fireStaff(r) } }
                }
                for i in 0..<17 where e.canBuyEquip(i) { thunks.append { e.buyEquip(i) } }
                if e.canUpgradeStudio { thunks.append { e.upgradeStudio() } }
                if e.canUpgradeLabel { thunks.append { e.upgradeLabel() } }
                guard !thunks.isEmpty else { acting = false; break }
                thunks[rng.randInt(0, thunks.count - 1)]()
            }
            if e.outcome.isOver { break }
            if e.canEndWeek {
                e.endWeek()
            } else if let s = (0..<ProducerEngine.rosterSlots).first(where: { e.canRelease(slot: $0) }) {
                e.release(slot: s)   // forced-release path of the TS driver
            } else if e.canSign {
                e.sign(candidate: 0)
            } else {
                break
            }
        }
        return e
    }

    func testRandomLegalAlwaysGoesBankruptFast() {
        var weeks: [Int] = []
        let n = 150
        var bankrupts = 0
        for i in 0..<n {
            let e = playRandomLegal(seed: UInt64(i) &* 7919 &+ 5)
            XCTAssertTrue(e.outcome.isOver)
            if e.outcome == .bankrupt { bankrupts += 1 }
            weeks.append(e.week)
        }
        // gate golden: 1000/1000 bankrupt, median 6 weeks
        XCTAssertGreaterThanOrEqual(Double(bankrupts) / Double(n), 0.95,
                                    "blind play must go bankrupt")
        XCTAssertLessThanOrEqual(weeks.sorted()[n / 2], 14,
                                 "blind play must die fast (gate median: 6 weeks)")
    }
}
