import XCTest
@testable import ProducerKit

final class ConstantsTests: XCTestCase {
    static let constants = try! GameConstants.load()
    static let world = try! CoevolvedWorld.load()
    var C: GameConstants { Self.constants }

    func testDimensionsMatchWorldConfig() {
        // the torchsim world_config dimension census
        XCTAssertEqual(C.genres.count, 6)
        XCTAssertEqual(C.archetypes.count, 8)
        XCTAssertEqual(C.trends.topics.count, 10)
        XCTAssertEqual(C.equipment.count, 17)
        XCTAssertEqual(C.staff.roles.count, 6)
        XCTAssertEqual(C.needs.count, 8)
        XCTAssertEqual(C.tiers.count, 5)
        XCTAssertEqual(C.weekEvents.count, 20)
        XCTAssertEqual(C.artistEvents.count, 17)
        XCTAssertEqual(C.traits.count, 30)
        XCTAssertEqual(C.studioUpgrades.count, 6)
        XCTAssertEqual(C.labelSlots.count, 6)
    }

    func testCanonicalOrdersCoverTheJSON() {
        XCTAssertEqual(Set(GameConstants.archetypeIDs), Set(C.archetypes.keys))
        XCTAssertEqual(Set(GameConstants.stats), Set(C.artistGen.statNorm.keys))
        for stat in C.scoreFormula.weights.keys {
            XCTAssertTrue(GameConstants.stats.contains(stat), "unknown weight stat \(stat)")
        }
        for ev in C.artistEvents {
            for stat in ev.fx.keys {
                XCTAssertTrue(GameConstants.stats.contains(stat), "unknown event stat \(stat)")
            }
        }
        for (_, fx) in C.archetypes {
            for stat in fx.keys {
                XCTAssertTrue(GameConstants.stats.contains(stat), "unknown archetype stat \(stat)")
            }
        }
        for topic in C.trends.genreAffinity.values.flatMap({ $0 }) {
            XCTAssertTrue(C.trends.topics.contains(topic))
        }
    }

    func testStartAndWinLose() {
        XCTAssertEqual(C.start.money, 20000)
        XCTAssertEqual(C.start.tokens, 3)
        XCTAssertEqual(C.start.reputation, 50)
        XCTAssertEqual(C.winLose.bankruptcyBelow, -50000)
        XCTAssertEqual(C.winLose.fansForVictory, 100_000_000)
        XCTAssertEqual(C.winLose.yearsForVictory, 10)
        XCTAssertEqual(C.winLose.rejectsForGameOver, 6)
    }

    func testThetaValuesMatchArtifact() {
        let t = Self.world.theta
        XCTAssertEqual(Self.world.target_win, 0.62)
        XCTAssertEqual(t.pay_mult_cult, 1.5882)
        XCTAssertEqual(t.pay_mult_normal, 0.6956)
        XCTAssertEqual(t.bankruptcy_floor, -52214.3376)
        XCTAssertEqual(t.fan_rate_mult, 0.6894)
        XCTAssertEqual(t.token_reward_mult, 0.8084)
        XCTAssertEqual(t.luck_spread_mult, 0.8458)
        XCTAssertEqual(t.start_money_mult, 0.9964)
    }

    func testNeutralThetaIsIdentity() {
        let t = Theta.neutral(C)
        XCTAssertEqual(t.payMult, [1, 1, 1, 1, 1])
        XCTAssertEqual(t.bankruptcy_floor, C.winLose.bankruptcyBelow)
        XCTAssertEqual(t.week_event_chance, C.weekly.weekEventChance)
        XCTAssertEqual(t.need_chance, C.weekly.needChance)
    }

    func testTextFitDistribution() {
        let table = try! TextFitTable.load()
        XCTAssertFalse(table.values.isEmpty)
        var rng = GameRandom(seed: 7)
        var sum = 0.0
        let n = 20000
        for _ in 0..<n { sum += table.sample(&rng) }
        // measured corpus mean is -7.58 (game_constants textLayer.fitMean)
        XCTAssertEqual(sum / Double(n), -7.58, accuracy: 0.2)
    }
}

final class GameRandomTests: XCTestCase {
    func testRandIntInclusiveBothEnds() {
        var rng = GameRandom(seed: 1)
        var seen = Set<Int>()
        for _ in 0..<10000 { seen.insert(rng.randInt(-2, 3)) }
        XCTAssertEqual(seen, Set([-2, -1, 0, 1, 2, 3]))
    }

    func testRandIntMean() {
        var rng = GameRandom(seed: 2)
        var sum = 0.0
        let n = 100_000
        for _ in 0..<n { sum += rng.randInt(-8.0, 8.0) }
        XCTAssertEqual(sum / Double(n), 0, accuracy: 0.1)
    }

    func testUniformBoundsAndMean() {
        var rng = GameRandom(seed: 3)
        var sum = 0.0
        let n = 100_000
        for _ in 0..<n {
            let v = rng.uniform(0.06, 0.12)
            XCTAssertGreaterThanOrEqual(v, 0.06)
            XCTAssertLessThan(v, 0.12)
            sum += v
        }
        XCTAssertEqual(sum / Double(n), 0.09, accuracy: 0.001)
    }

    func testGaussianMoments() {
        var rng = GameRandom(seed: 4)
        var sum = 0.0, sq = 0.0
        let n = 200_000
        for _ in 0..<n {
            let g = rng.gaussian()
            sum += g
            sq += g * g
        }
        XCTAssertEqual(sum / Double(n), 0, accuracy: 0.01)
        XCTAssertEqual(sq / Double(n), 1, accuracy: 0.02)
    }

    func testWeightedIndexSkipsZeroWeights() {
        var rng = GameRandom(seed: 5)
        for _ in 0..<2000 {
            let i = rng.weightedIndex([0, 3, 0, 1, 0])
            XCTAssertTrue(i == 1 || i == 3)
        }
    }

    func testDeterminismAcrossSameSeed() {
        var a = GameRandom(seed: 42)
        var b = GameRandom(seed: 42)
        for _ in 0..<100 {
            XCTAssertEqual(a.next(), b.next())
        }
    }
}
