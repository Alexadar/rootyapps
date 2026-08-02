import Foundation

public enum GameOutcome: Equatable {
    case running
    case winFans        // 100M fans
    case winYears       // survived 10 years with a roster
    case bankrupt       // money below the (theta) bankruptcy floor
    case reputationLost // reputation hit 0
    case rejectedOut    // empty roster + too many rejects
    case timeout

    public var isWin: Bool { self == .winFans || self == .winYears }
    public var isOver: Bool { self != .running }
}

public struct ReleaseReport {
    public let artistName: String
    public let score: Double
    public let tier: Int
    public let tierName: String
    public let fansGained: Double
    public let moneyDelta: Double
    public let tokensGained: Double
}

public struct TourReport {
    public let artistName: String
    public let success: Bool
    public let moneyDelta: Double
    public let fansGained: Double
}

public struct WeekReport {
    public let salaries: Double
    public let weekEvent: GameConstants.WeekEvent?
    public let outcome: GameOutcome
}

/// One-session Producer Tycoon engine: a scalar port of the torchsim batched
/// env (`env_producer.py`), which is itself rule-parity-validated (102/102
/// KS statistics) against the TypeScript game. Runs the co-evolved world:
/// theta knobs + the adaptive dealer as the candidate source.
public final class ProducerEngine {
    public static let rosterSlots = 12
    public static let maxActionsPerWeek = 16
    public static let maxWeeks = 520

    public let constants: GameConstants
    public let theta: Theta
    public internal(set) var rng: GameRandom
    let dealer: Dealer?
    var dealerMemory = DealerMemory()
    let textFitTable: TextFitTable
    let difficulty: Double

    // --- label state ---
    public internal(set) var money: Double = 0
    public internal(set) var fans: Double = 0
    public internal(set) var tokens: Double = 0
    public internal(set) var rep: Double = 0
    public internal(set) var week = 0
    public internal(set) var studioLevel = 1        // 1...6
    public internal(set) var labelTier = 0          // 0...5
    public internal(set) var prodLevel: Double = 1
    public internal(set) var prodXP: Double = 0
    public internal(set) var prodXPNext: Double
    public internal(set) var releases: Double = 0
    public internal(set) var rejects: Double = 0
    public internal(set) var weekActions = 0
    public internal(set) var weekAdvanced = false   // endWeek locked until a release
    public internal(set) var equipOwned: [Bool]
    public internal(set) var staffHired: [Bool]
    public internal(set) var roster: [Artist?]
    public internal(set) var candidates: [Artist] = []
    public internal(set) var topicPop: [Double] = []
    public internal(set) var topicDir: [Int] = []   // 0 rising / 1 peaking / 2 falling
    public internal(set) var genrePop: [Double] = []
    public internal(set) var genreMod: [Double] = []
    public internal(set) var outcome: GameOutcome = .running

    public convenience init(constants: GameConstants, world: CoevolvedWorld?,
                            textFitTable: TextFitTable, seed: UInt64) {
        self.init(constants: constants,
                  theta: world?.theta ?? .neutral(constants),
                  dealer: world.map { Dealer(params: $0.dealer.params) },
                  difficulty: world?.target_win ?? 0.62,
                  textFitTable: textFitTable, seed: seed)
    }

    /// Designated initializer with explicit theta/dealer (tests use this to
    /// pin chances to 0/1 for deterministic weekly-transition assertions).
    public init(constants: GameConstants, theta: Theta, dealer: Dealer?,
                difficulty: Double, textFitTable: TextFitTable, seed: UInt64) {
        self.constants = constants
        self.theta = theta
        self.dealer = dealer
        self.difficulty = difficulty
        self.textFitTable = textFitTable
        self.rng = GameRandom(seed: seed)
        self.prodXPNext = constants.scoreFormula.expToNextBase
        self.equipOwned = Array(repeating: false, count: constants.equipment.count)
        self.staffHired = Array(repeating: false, count: constants.staff.roles.count)
        self.roster = Array(repeating: nil, count: Self.rosterSlots)
        resetState()
    }

    /// Convenience: load bundled constants + the co-evolved world artifact.
    public static func coevolved(seed: UInt64) throws -> ProducerEngine {
        ProducerEngine(constants: try .load(), world: try .load(),
                       textFitTable: try .load(), seed: seed)
    }

    func resetState() {
        let c = constants
        money = c.start.money * theta.start_money_mult
        fans = c.start.fans
        tokens = c.start.tokens
        rep = c.start.reputation
        week = 0
        studioLevel = c.start.studioLevel
        labelTier = c.start.labelSlotIndex
        outcome = .running
        let tr = c.trends
        topicPop = (0..<tr.topics.count).map { _ in rng.randInt(tr.initTopicPop[0], tr.initTopicPop[1]) }
        topicDir = (0..<tr.topics.count).map { _ in
            let u = rng.next()
            return u < 0.4 ? 0 : (u < 0.58 ? 2 : 1)
        }
        genrePop = Array(repeating: 50, count: c.genres.count)
        genreMod = Array(repeating: 0, count: c.genres.count)
        updateTrends()
        newPair()
    }

    // MARK: - derived quantities

    public var rosterCount: Int { roster.compactMap { $0 }.count }
    public var labelSlots: Int { constants.labelSlots[labelTier].slots }

    var staffEffects: ReleaseMath.StaffEffects {
        .init(hired: staffHired, roles: constants.staff.roles, bonuses: constants.staff.bonuses)
    }

    var equipBonus: Double {
        zip(equipOwned, constants.equipment).reduce(0) { $0 + ($1.0 ? $1.1.bonus : 0) }
    }

    public func studioUpgradeCost() -> Double? {
        guard studioLevel < 6 else { return nil }
        return constants.studioUpgrades[min(studioLevel, 5)].cost * theta.upgrade_cost_mult
    }

    public func labelUpgradeCost() -> Double? {
        guard labelTier < 5 else { return nil }
        return constants.labelSlots[min(labelTier + 1, 5)].cost * theta.upgrade_cost_mult
    }

    public func equipCost(_ index: Int) -> Double {
        constants.equipment[index].cost * theta.equip_cost_mult
    }

    public func tourCost(slot: Int) -> Double? {
        guard let a = roster[slot] else { return nil }
        return TourMath.cost(popularity: a[stat: "popularity"], tour: constants.tour, theta: theta)
    }

    public func needCost(slot: Int) -> Double? {
        guard let a = roster[slot], a.needActive else { return nil }
        return constants.needs[a.needID].cost
    }

    // MARK: - legality (mirrors env legal_mask)

    /// After 16 in-week actions only endWeek remains — unless endWeek itself
    /// is locked, in which case release/sign stay legal as the escape hatch.
    var actionCapped: Bool { weekActions >= Self.maxActionsPerWeek }
    func capAllows(releaseOrSign: Bool) -> Bool {
        !actionCapped || (releaseOrSign && weekAdvanced)
    }

    public var canEndWeek: Bool { outcome == .running && !weekAdvanced }
    public var canSign: Bool {
        outcome == .running && rosterCount < labelSlots && capAllows(releaseOrSign: true)
    }
    public var canReject: Bool { outcome == .running && !actionCapped }
    public func canRelease(slot: Int) -> Bool {
        outcome == .running && roster[slot] != nil && tokens >= 1 && capAllows(releaseOrSign: true)
    }
    public func canTour(slot: Int) -> Bool {
        guard outcome == .running, !actionCapped, let a = roster[slot], a.tourCooldown <= 0,
              let cost = tourCost(slot: slot) else { return false }
        return money >= cost
    }
    public func canRehab(slot: Int) -> Bool {
        guard outcome == .running, !actionCapped, let a = roster[slot] else { return false }
        return !a.inRehab && money >= constants.rehab.cost
    }
    public func canFire(slot: Int) -> Bool {
        outcome == .running && !actionCapped && roster[slot] != nil
    }
    public func canFulfillNeed(slot: Int) -> Bool {
        guard outcome == .running, !actionCapped, let a = roster[slot], a.needActive else { return false }
        return money >= constants.needs[a.needID].cost
    }
    public func canHireStaff(_ i: Int) -> Bool { outcome == .running && !actionCapped && !staffHired[i] }
    public func canFireStaff(_ i: Int) -> Bool { outcome == .running && !actionCapped && staffHired[i] }
    public func canBuyEquip(_ i: Int) -> Bool {
        outcome == .running && !actionCapped && !equipOwned[i] && money >= equipCost(i)
    }
    public var canUpgradeStudio: Bool {
        guard outcome == .running, !actionCapped, let c = studioUpgradeCost() else { return false }
        return money >= c
    }
    public var canUpgradeLabel: Bool {
        guard outcome == .running, !actionCapped, let c = labelUpgradeCost() else { return false }
        return money >= c
    }

    func countAction() { weekActions += 1 }

    // MARK: - actions

    @discardableResult
    public func sign(candidate index: Int) -> Bool {
        guard canSign, index < candidates.count,
              let free = roster.firstIndex(where: { $0 == nil }) else { return false }
        countAction()
        roster[free] = candidates[index]
        rejects = 0
        newPair()
        return true
    }

    @discardableResult
    public func rejectPair() -> Bool {
        guard canReject else { return false }
        countAction()
        rejects += 2
        newPair()
        return true
    }

    @discardableResult
    public func release(slot: Int) -> ReleaseReport? {
        guard canRelease(slot: slot), var a = roster[slot] else { return nil }
        countAction()
        let sf = constants.scoreFormula
        let staff = staffEffects
        let luck = rng.randInt(sf.luck[0], sf.luck[1]) * theta.luck_spread_mult
        let score = ReleaseMath.score(
            stats: a.stats, sf: sf, equipBonus: equipBonus, staff: staff,
            prodLevel: prodLevel, studioLevel: Double(studioLevel),
            studioQuality: constants.studioUpgrades[clamp(studioLevel - 1, 0, 5)].qualityBonus,
            genreMod: genreMod[a.genre], trashPop: a.trashPop,
            traitScore: a.traitScore, traitChaos: a.traitChaos, textFit: a.textFit,
            luck: luck)
        let tier = ReleaseMath.tier(score: score, thresholds: sf.tierThresholds)
        let t = constants.tiers[tier]
        let listeners = rng.randInt(t.listeners[0], t.listeners[1])
        let eco = ReleaseMath.economics(
            listeners: listeners,
            fanRateRoll: rng.uniform(t.fanRate[0], t.fanRate[1]),
            payRateRoll: rng.uniform(t.payRate[0], t.payRate[1]),
            costRoll: rng.randInt(t.cost[0], t.cost[1]),
            tokenRoll: rng.randInt(t.tokenReward[0], t.tokenReward[1]),
            tierPayMult: theta.payMult[tier], theta: theta, staff: staff)
        money += eco.moneyDelta
        fans = max(0, fans + eco.fansGained)
        tokens += eco.tokensGained - 1
        releases += 1
        let pop = a[stat: "popularity"]
        a[stat: "popularity"] = clamp(pop + ReleaseMath.popBoost(score: score, pb: sf.popBoost), 10, 90)
        roster[slot] = a
        (prodXP, prodLevel, prodXPNext) = ReleaseMath.applyXP(
            xp: prodXP, level: prodLevel, xpNext: prodXPNext, gain: sf.expGain[tier], sf: sf)
        rep = clamp(rep + sf.repChange[tier], 0, 100)
        weekAdvanced = false
        return ReleaseReport(artistName: a.name, score: score, tier: tier, tierName: t.name,
                             fansGained: eco.fansGained, moneyDelta: eco.moneyDelta,
                             tokensGained: eco.tokensGained)
    }

    @discardableResult
    public func tour(slot: Int) -> TourReport? {
        guard canTour(slot: slot), var a = roster[slot] else { return nil }
        countAction()
        let tour = constants.tour
        let managerEffect = staffHired[constants.staff.roles.firstIndex(of: "manager")!]
            ? constants.staff.bonuses["manager"]! * 0.5 : 0
        let total = TourMath.total(stats: a.stats, tour: tour, genreMod: genreMod[a.genre],
                                   managerEffect: managerEffect,
                                   luck: rng.randInt(tour.luck[0], tour.luck[1]))
        let success = total >= tour.successThreshold
        let pop = a[stat: "popularity"]
        let revNoise = success
            ? rng.randInt(tour.success.revNoise[0], tour.success.revNoise[1])
            : rng.randInt(tour.fail.revNoise[0], tour.fail.revNoise[1])
        let failFanRoll = success ? 0
            : rng.randInt(tour.fail.fansMin, max(tour.fail.fansMin, tsRound(pop * tour.fail.fansPerPopMax)))
        let result = TourMath.outcome(total: total, popularity: pop, tour: tour, theta: theta,
                                      revNoise: revNoise, failFanRoll: failFanRoll)
        money += result.moneyDelta
        fans += result.fansGained
        if success {
            a[stat: "popularity"] = clamp(pop + rng.randInt(tour.onSuccess.popGain[0], tour.onSuccess.popGain[1]), 10, 90)
            a[stat: "happiness"] = clamp(a[stat: "happiness"] + tour.onSuccess.happinessGain, 10, 90)
        } else {
            a[stat: "popularity"] = clamp(pop - rng.randInt(tour.onFail.popLoss[0], tour.onFail.popLoss[1]), 10, 90)
            a[stat: "happiness"] = clamp(a[stat: "happiness"] - tour.onFail.happinessLoss, 10, 90)
            a[stat: "health"] = clamp(a[stat: "health"] - tour.onFail.healthLoss, 10, 90)
        }
        a.tourCooldown = tour.cooldownWeeks
        roster[slot] = a
        return TourReport(artistName: a.name, success: success,
                          moneyDelta: result.moneyDelta, fansGained: result.fansGained)
    }

    @discardableResult
    public func rehab(slot: Int) -> Bool {
        guard canRehab(slot: slot), var a = roster[slot] else { return false }
        countAction()
        money -= constants.rehab.cost
        a.inRehab = true
        a.rehabWeeks = constants.rehab.weeks
        a[stat: "addiction"] = clamp(a[stat: "addiction"] - constants.rehab.addictionDrop, 10, 90)
        roster[slot] = a
        return true
    }

    @discardableResult
    public func fire(slot: Int) -> Bool {
        guard canFire(slot: slot) else { return false }
        countAction()
        roster[slot] = nil
        return true
    }

    @discardableResult
    public func fulfillNeed(slot: Int) -> Bool {
        guard canFulfillNeed(slot: slot), var a = roster[slot] else { return false }
        countAction()
        money -= constants.needs[a.needID].cost
        a[stat: "happiness"] = clamp(a[stat: "happiness"] + constants.needFulfillHappiness, 10, 90)
        a.needActive = false
        roster[slot] = a
        return true
    }

    @discardableResult
    public func hireStaff(_ i: Int) -> Bool {
        guard canHireStaff(i) else { return false }
        countAction()
        staffHired[i] = true
        return true
    }

    @discardableResult
    public func fireStaff(_ i: Int) -> Bool {
        guard canFireStaff(i) else { return false }
        countAction()
        staffHired[i] = false
        return true
    }

    @discardableResult
    public func buyEquip(_ i: Int) -> Bool {
        guard canBuyEquip(i) else { return false }
        countAction()
        money -= equipCost(i)
        equipOwned[i] = true
        return true
    }

    @discardableResult
    public func upgradeStudio() -> Bool {
        guard canUpgradeStudio, let cost = studioUpgradeCost() else { return false }
        countAction()
        money -= cost
        studioLevel += 1
        return true
    }

    @discardableResult
    public func upgradeLabel() -> Bool {
        guard canUpgradeLabel, let cost = labelUpgradeCost() else { return false }
        countAction()
        money -= cost
        labelTier += 1
        return true
    }

    // MARK: - weekly transition

    @discardableResult
    public func endWeek() -> WeekReport? {
        guard canEndWeek else { return nil }
        let wk = constants.weekly
        let archFx = constants.archetypeEffects

        for slot in 0..<Self.rosterSlots {
            guard var a = roster[slot] else { continue }
            // 1. archetype weekly effects + jitter
            var stx = zip(a.stats, archFx[a.archetype]).map(+)
            for (stat, range) in wk.jitter {
                stx[GameConstants.statIndex(stat)] += rng.randInt(range[0], range[1])
            }
            // 2. conditionals read the post-archetype/jitter values
            var cond = [Double](repeating: 0, count: stx.count)
            let hap = stx[GameConstants.statIndex("happiness")]
            let health = stx[GameConstants.statIndex("health")]
            let add = stx[GameConstants.statIndex("addiction")]
            if hap < wk.lowHappiness.below! {
                cond[GameConstants.statIndex("discipline")] += wk.lowHappiness.discipline!
            }
            if health < wk.lowHealth.below! {
                cond[GameConstants.statIndex("happiness")] += wk.lowHealth.happiness!
                cond[GameConstants.statIndex("discipline")] += wk.lowHealth.discipline!
            }
            if add > wk.highAddiction.above! {
                cond[GameConstants.statIndex("health")] += wk.highAddiction.health!
                cond[GameConstants.statIndex("happiness")] += wk.highAddiction.happiness!
            }
            stx = zip(stx, cond).map(+)
            // 3. freak emergence
            let fe = wk.freakEmergence
            if stx[GameConstants.statIndex("selfConfidence")] > fe.selfConfidenceAbove,
               stx[GameConstants.statIndex("talent")] < fe.talentBelow,
               rng.chance(fe.chance) {
                a.trashPop = clamp(a.trashPop + rng.randInt(fe.trashPopGain[0], fe.trashPopGain[1]),
                                   fe.trashPopClamp[0], fe.trashPopClamp[1])
                stx[GameConstants.statIndex("popularity")] += rng.randInt(fe.popGain[0], fe.popGain[1])
            }
            // 4. rehab tick
            if a.inRehab {
                a.rehabWeeks -= 1
                stx[GameConstants.statIndex("health")] =
                    clamp(stx[GameConstants.statIndex("health")] + constants.rehab.weeklyHealthGain, 10, 90)
                stx[GameConstants.statIndex("addiction")] =
                    clamp(stx[GameConstants.statIndex("addiction")] - constants.rehab.weeklyAddictionDrop, 10, 90)
                a.inRehab = a.rehabWeeks > 0
            }
            // 5. needs: tick, expire with penalty, maybe new
            if a.needActive {
                a.needWeeks -= 1
                if a.needWeeks <= 0 {
                    stx[GameConstants.statIndex("happiness")] -= constants.needs[a.needID].happinessPenalty
                    a.needActive = false
                }
            }
            if !a.inRehab, !a.needActive, rng.chance(theta.need_chance * wk.needInnerChance) {
                a.needID = rng.randInt(0, constants.needs.count - 1)
                a.needWeeks = wk.needWeeks
                a.needActive = true
            }
            // 6. artist events (weighted pick among gate-eligible templates)
            if rng.chance(theta.artist_event_chance) {
                let add2 = stx[GameConstants.statIndex("addiction")]
                let hap2 = stx[GameConstants.statIndex("happiness")]
                let weights = constants.artistEvents.map { e in
                    (add2 >= e.add[0] && add2 <= e.add[1] && hap2 >= e.hap[0] && hap2 <= e.hap[1]) ? e.w : 0
                }
                if weights.reduce(0, +) > 0 {
                    let ev = constants.artistEvents[rng.weightedIndex(weights)]
                    for (stat, range) in ev.fx {
                        stx[GameConstants.statIndex(stat)] += rng.randInt(range[0], range[1])
                    }
                }
            }
            // 7. clamp all stats
            a.stats = stx.map { clamp($0, wk.statClamp[0], wk.statClamp[1]) }
            // 8. tour cooldown tick
            a.tourCooldown = max(0, a.tourCooldown - 1)
            roster[slot] = a
        }

        // 9. staff salaries + week event
        let salaries = zip(staffHired, constants.staff.roles)
            .reduce(0.0) { $0 + ($1.0 ? constants.staff.salaries[$1.1]! : 0) } * theta.salary_mult
        money -= salaries
        var weekEvent: GameConstants.WeekEvent?
        var tokenDelta = 0.0
        if rng.chance(theta.week_event_chance) {
            let ev = constants.weekEvents[rng.randInt(0, constants.weekEvents.count - 1)]
            weekEvent = ev
            money += ev.money
            fans = max(0, fans + ev.fans)
            rep = clamp(rep + ev.rep, 0, 100)
            tokenDelta = ev.tokens
        }
        tokens = max(tokens + tokenDelta, wk.tokenStipendMin)

        // 10. trends drift
        updateTrends()

        // 11. win/lose (victory has precedence over game-over)
        week += 1
        let wl = constants.winLose
        let victoryWeeks = Int(wl.yearsForVictory) * 48
        if fans >= wl.fansForVictory { outcome = .winFans }
        else if week >= victoryWeeks && rosterCount > 0 { outcome = .winYears }
        else if money < theta.bankruptcy_floor { outcome = .bankrupt }
        else if rep <= wl.repGameOverAt { outcome = .reputationLost }
        else if rosterCount == 0 && rejects > wl.rejectsForGameOver { outcome = .rejectedOut }
        else if week >= Self.maxWeeks { outcome = .timeout }

        // 12. week reset
        newPair()
        rejects = 0
        weekActions = 0
        weekAdvanced = true
        return WeekReport(salaries: salaries, weekEvent: weekEvent, outcome: outcome)
    }

    // MARK: - trends (parity with env `_update_trends`)

    func updateTrends() {
        let tr = constants.trends
        // topics
        for i in 0..<topicPop.count {
            topicPop[i] = clamp(topicPop[i] + rng.randInt(tr.topicDrift[0], tr.topicDrift[1]),
                                tr.topicClamp[0], tr.topicClamp[1])
            let u = rng.next()
            if topicDir[i] == 0 && topicPop[i] > 70 { topicDir[i] = 1 }
            if topicDir[i] == 1 && u < 0.4 { topicDir[i] = 2 }
            if topicDir[i] == 2 && topicPop[i] < 30 { topicDir[i] = 0 }
        }
        // genres: affinity influence summed over each genre's topics
        for (gi, gid) in constants.genres.enumerated() {
            var infl = 0.0
            for topic in tr.genreAffinity[gid] ?? [] {
                let ti = tr.topics.firstIndex(of: topic)!
                infl += (topicPop[ti] > 60 ? 1 : 0) - (topicPop[ti] < 30 ? 1 : 0)
                    + (topicDir[ti] == 0 ? 1 : 0) - (topicDir[ti] == 2 ? 1 : 0)
            }
            let old = genrePop[gi]
            var new = old + rng.randInt(tr.genreStep[0], tr.genreStep[1])
                + tsRound(tr.genreDrift[gid]! * tr.genreDriftMult) + infl
            if rng.chance(tr.genreJumpChance) {
                new += rng.randInt(tr.genreJump[0], tr.genreJump[1])
            }
            new = old + clamp(new - old, -tr.genreMaxChange, tr.genreMaxChange)
            new = clamp(tsRound(new), tr.genreClamp[0], tr.genreClamp[1])
            genrePop[gi] = new
            genreMod[gi] = clamp(tsRound((new - old) * tr.modMult)
                                 + rng.randInt(tr.modNoise[0], tr.modNoise[1]),
                                 tr.modClamp[0], tr.modClamp[1])
        }
    }

    // MARK: - candidate generation

    func newPair() {
        if let dealer {
            let ctx = dealerContext()
            let raw = dealer.forward(ctx: ctx, memory: dealerMemory.tokens, used: dealerMemory.used)
            var pair: [Artist] = []
            var memTokens: [[Double]] = []
            for c in 0..<2 {
                let s = dealer.sample(block: raw[(c * Dealer.outPerCand)..<((c + 1) * Dealer.outPerCand)],
                                      rng: &rng)
                memTokens.append(s.memoryToken)
                pair.append(Artist(name: ArtistNames.generate(&rng),
                                   stats: s.stats, genre: s.genre, archetype: s.archetype,
                                   traitScore: s.traitScore, traitChaos: s.traitChaos,
                                   textFit: textFitTable.sample(&rng)))
            }
            dealerMemory.push(memTokens)
            candidates = pair
        } else {
            candidates = [bankArtist(), bankArtist()]
        }
    }

    /// Dealer conditioning vector (parity with `dealer.make_candidate_source`).
    func dealerContext() -> [Double] {
        let alive = roster.compactMap { $0 }
        let meanExp = alive.isEmpty ? 0
            : alive.map { ($0.stats[0] + $0.stats[1] + $0.stats[2]) / 3 }.reduce(0, +) / Double(alive.count)
        return [
            difficulty,
            Double(week) / 480.0,
            clamp(log1p(max(fans, 0)) / log1p(1e8), 0, 1.2),
            clamp((money < 0 ? -1.0 : money > 0 ? 1.0 : 0.0) * log1p(abs(money) / 1e3) / 8, -1.25, 1.25),
            Double(rosterCount) / 12.0,
            meanExp / 100.0,
            clamp(tokens / 8.0, 0, 2),
            1.0,
        ]
    }

    /// I.i.d. artist matching src/lib/generateArtist.ts distributions —
    /// the fallback content source when no dealer is loaded (neutral world).
    func bankArtist() -> Artist {
        let gen = constants.artistGen
        var stats = [Double](repeating: 0, count: GameConstants.stats.count)
        for (stat, ms) in gen.statNorm {
            stats[GameConstants.statIndex(stat)] = clamp(tsRound(ms[0] + rng.gaussian() * ms[1]), 10, 90)
        }
        let genre = rng.randInt(0, constants.genres.count - 1)
        let arch = rng.randInt(0, GameConstants.archetypeIDs.count - 1)
        for (stat, bias) in gen.genreBias[constants.genres[genre]] ?? [:] {
            let i = GameConstants.statIndex(stat)
            stats[i] = clamp(stats[i] + bias, 10, 90)
        }
        let nTraits = rng.randInt(gen.traitsCount[0], gen.traitsCount[1])
        var pool = Array(constants.traits.indices)
        var traitScore = 0.0, traitChaos = 0.0
        for _ in 0..<nTraits {
            let pick = pool.remove(at: rng.randInt(0, pool.count - 1))
            traitScore += constants.traits[pick].score
            traitChaos += constants.traits[pick].chaos
        }
        return Artist(name: ArtistNames.generate(&rng), stats: stats, genre: genre,
                      archetype: arch, traitScore: traitScore, traitChaos: traitChaos,
                      textFit: textFitTable.sample(&rng))
    }
}
