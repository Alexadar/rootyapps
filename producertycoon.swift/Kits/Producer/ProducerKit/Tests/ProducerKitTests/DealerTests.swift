import XCTest
@testable import ProducerKit

/// Dealer network parity: forward-pass goldens computed with float64 numpy
/// from the ACTUAL world_coevolved.json weights (scratchpad make_goldens.py).
final class DealerTests: XCTestCase {
    static let world = try! CoevolvedWorld.load()
    static let dealer = Dealer(params: world.dealer.params)

    /// ctx of a fresh coevolved game: d=0.62, week 0, no fans, start money
    /// 20000 * 0.9964, empty roster, 3 tokens.
    static let ctx0: [Double] = {
        let money = 20000 * world.theta.start_money_mult
        return [0.62, 0, 0, log1p(money / 1e3) / 8, 0, 0, 3.0 / 8, 1]
    }()

    func testParamCountMatchesArtifact() {
        XCTAssertEqual(Dealer.paramCount, 4024)
        XCTAssertEqual(Self.world.dealer.n_params, 4024)
        XCTAssertEqual(Self.world.dealer.params.count, 4024)
    }

    func testCtxMoneyTermGolden() {
        XCTAssertEqual(Self.ctx0[3], 0.3801359969093485, accuracy: 1e-12)
    }

    func testForwardGoldenEmptyMemory() {
        let mem = DealerMemory()
        let out = Self.dealer.forward(ctx: Self.ctx0, memory: mem.tokens, used: mem.used)
        XCTAssertEqual(out.count, 72)
        let expected: [Double] = [9.50427711209995, -0.29021595454910165, -4.955347077901211,
                                  1.561504635709431, 1.6212761492331245, 2.503327360168453,
                                  -4.621512976192688, -10.087159226011515]
        for (i, e) in expected.enumerated() {
            XCTAssertEqual(out[i], e, accuracy: 1e-8, "out[\(i)]")
        }
        XCTAssertEqual(out.reduce(0, +), 232.21050155122572, accuracy: 1e-7)
    }

    func testForwardGoldenWithMemory() {
        let memA: [Double] = [0.25, -0.5, 0.1, 0.0, 0.75, -0.25, 0.5, 0.2, -0.1,
                              2.0 / 6, 5.0 / 8, 0.35, 0.42]
        let memB: [Double] = [-0.3, 0.6, 0.05, 0.9, -0.8, 0.15, 0.0, -0.55, 0.33,
                              4.0 / 6, 1.0 / 8, -0.7, 0.11]
        var mem = DealerMemory()
        mem.push([memA, memB])   // lands in ring slots 6, 7 with used = 1
        let out = Self.dealer.forward(ctx: Self.ctx0, memory: mem.tokens, used: mem.used)
        let expected: [Double] = [10.333075411320735, -2.3300567469372764, -5.54353470213825,
                                  -1.4759708446772288, -2.6115114472961483, 4.870118288665043,
                                  -9.102358150617992, -11.273355063679567]
        for (i, e) in expected.enumerated() {
            XCTAssertEqual(out[i], e, accuracy: 1e-8, "out[\(i)]")
        }
        XCTAssertEqual(out.reduce(0, +), 241.65620703504763, accuracy: 1e-7)
    }

    func testDecodeHeadGoldens() {
        let mem = DealerMemory()
        let out = Self.dealer.forward(ctx: Self.ctx0, memory: mem.tokens, used: mem.used)
        // deterministic decode heads of candidate 0
        func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-x)) }
        XCTAssertEqual(sigmoid(out[0]) * 80 + 10, 89.99403785526047, accuracy: 1e-8)
        XCTAssertEqual(sigmoid(out[1]) * 80 + 10, 44.2360798913227, accuracy: 1e-8)
        XCTAssertEqual(sigmoid(out[2]) * 80 + 10, 10.559707264895739, accuracy: 1e-8)
        XCTAssertEqual(tanh(out[32]) * 15, -14.999999920362564, accuracy: 1e-8)
        let g = Array(out[18..<24])
        let mx = g.max()!
        let e = g.map { exp($0 - mx) }
        let s = e.reduce(0, +)
        XCTAssertEqual(e[0] / s, 0.5046116349275176, accuracy: 1e-9)
        XCTAssertEqual(e[1] / s, 0.48129094324707355, accuracy: 1e-9)
    }

    func testMemoryRingShiftsByTwo() {
        var mem = DealerMemory()
        let a = [Double](repeating: 1, count: 13)
        let b = [Double](repeating: 2, count: 13)
        let c = [Double](repeating: 3, count: 13)
        let d = [Double](repeating: 4, count: 13)
        mem.push([a, b])
        XCTAssertEqual(mem.used, [0, 0, 0, 0, 0, 0, 1, 1])
        XCTAssertEqual(mem.tokens[6], a)
        XCTAssertEqual(mem.tokens[7], b)
        mem.push([c, d])
        XCTAssertEqual(mem.used, [0, 0, 0, 0, 1, 1, 1, 1])
        XCTAssertEqual(mem.tokens[4], a)
        XCTAssertEqual(mem.tokens[5], b)
        XCTAssertEqual(mem.tokens[6], c)
        XCTAssertEqual(mem.tokens[7], d)
        // ring capacity: after 4 pushes the first pair falls out
        mem.push([a, b])
        mem.push([c, d])
        XCTAssertEqual(mem.tokens[0], a)
        XCTAssertEqual(mem.used, [Double](repeating: 1, count: 8))
    }

    func testSampledArtistsRespectBounds() {
        var rng = GameRandom(seed: 99)
        let mem = DealerMemory()
        let out = Self.dealer.forward(ctx: Self.ctx0, memory: mem.tokens, used: mem.used)
        for _ in 0..<500 {
            for c in 0..<2 {
                let s = Self.dealer.sample(
                    block: out[(c * Dealer.outPerCand)..<((c + 1) * Dealer.outPerCand)],
                    rng: &rng)
                XCTAssertEqual(s.stats.count, 9)
                for v in s.stats {
                    XCTAssertGreaterThanOrEqual(v, 10)
                    XCTAssertLessThanOrEqual(v, 90)
                    XCTAssertEqual(v, v.rounded(), "stats are integers")
                }
                XCTAssertTrue((0..<6).contains(s.genre))
                XCTAssertTrue((0..<8).contains(s.archetype))
                XCTAssertTrue((-15.0...21.0).contains(s.traitScore))
                XCTAssertTrue((0.0...10.0).contains(s.traitChaos))
                XCTAssertEqual(s.memoryToken.count, 13)
            }
        }
    }
}
