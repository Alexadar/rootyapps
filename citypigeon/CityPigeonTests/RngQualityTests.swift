import XCTest
import MLX
@testable import CityPigeon

/// The engine's counter-based RNG, tested for the property that actually failed.
///
/// A previous version was a pure Lehmer chain: `h = (idx·A + base)·Aⁿ mod M`, **affine in the index**.
/// Each lane's value was therefore lane 0's plus a fixed constant, so the lanes were perfectly
/// correlated. Every lane looked uniform on its own; nothing was uniform *jointly*.
///
/// It surfaced as a gameplay bug and not as a statistics one. The flock spawns only on frames where
/// lane 4 rolls below 0.02, and on that conditioned subset lanes 5–7 were nearly constant: eight
/// consecutive birds arrived at almost the same altitude, all travelling the same direction. The
/// lesson is the shape of the test below — **a per-lane uniformity check would have passed.**
final class RngQualityTests: XCTestCase {

    private func lanes(_ frames: Int, lanes L: Int = 8) -> [[Double]] {
        (0..<frames).map { f in
            Rng.uniforms(batch: 1, lanes: L, seed: 0xBEEF, frame: f)
                .asArray(Float.self).map(Double.init)
        }
    }

    /// Each lane is uniform on its own. This is the weak check — it passed while the RNG was broken.
    func testEachLaneIsUniformOnItsOwn() {
        let rows = lanes(4000)
        for lane in 0..<8 {
            let v = rows.map { $0[lane] }
            let mean = v.reduce(0, +) / Double(v.count)
            XCTAssertEqual(mean, 0.5, accuracy: 0.03, "lane \(lane) mean \(mean)")
            XCTAssertLessThan(v.min()!, 0.02, "lane \(lane) never produces small values")
            XCTAssertGreaterThan(v.max()!, 0.98, "lane \(lane) never produces large values")
        }
    }

    /// **The check that matters: lanes must be independent of each other.**
    ///
    /// Condition on one lane landing in a narrow band — exactly what the spawn logic does — and the
    /// others must still look uniform. Under the affine chain, conditioning on lane 4 pinned lane 7
    /// to a near-constant, and this is where that shows up.
    func testLanesStayUniformWhenConditionedOnAnotherLane() {
        let rows = lanes(20000)
        for conditioning in 0..<8 {
            let subset = rows.filter { $0[conditioning] < 0.05 }
            XCTAssertGreaterThan(subset.count, 300,
                                 "not enough samples to judge lane \(conditioning)")
            for other in 0..<8 where other != conditioning {
                let v = subset.map { $0[other] }
                let mean = v.reduce(0, +) / Double(v.count)
                let spread = v.max()! - v.min()!
                XCTAssertEqual(mean, 0.5, accuracy: 0.08,
                               "conditioned on lane \(conditioning) < 0.05, lane \(other) has mean "
                               + "\(mean) — the lanes are correlated")
                XCTAssertGreaterThan(spread, 0.85,
                                     "conditioned on lane \(conditioning) < 0.05, lane \(other) only "
                                     + "spans \(spread) of its range")
            }
        }
    }

    /// Pairwise linear correlation, which an affine relationship maxes out at ±1.
    func testLanesAreNotLinearlyCorrelated() {
        let rows = lanes(8000)
        var worst = 0.0, worstPair = (0, 0)
        for a in 0..<8 {
            for b in (a + 1)..<8 {
                let x = rows.map { $0[a] }, y = rows.map { $0[b] }
                let mx = x.reduce(0, +) / Double(x.count), my = y.reduce(0, +) / Double(y.count)
                let cov = zip(x, y).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
                let sx = x.map { ($0 - mx) * ($0 - mx) }.reduce(0, +).squareRoot()
                let sy = y.map { ($0 - my) * ($0 - my) }.reduce(0, +).squareRoot()
                let r = abs(cov / (sx * sy))
                if r > worst { worst = r; worstPair = (a, b) }
            }
        }
        print(String(format: "RNG: worst pairwise |r| = %.4f between lanes %d and %d",
                     worst, worstPair.0, worstPair.1))
        XCTAssertLessThan(worst, 0.06, "lanes \(worstPair) are linearly correlated")
    }

    /// Still deterministic and still batch-invariant — the properties the mixing must not cost.
    func testStillDeterministicAndBatchInvariant() {
        let a = Rng.uniforms(batch: 1, lanes: 8, seed: 7, frame: 99).asArray(Float.self)
        let b = Rng.uniforms(batch: 1, lanes: 8, seed: 7, frame: 99).asArray(Float.self)
        XCTAssertEqual(a, b, "the same (seed, frame) gave different draws")

        let solo = Rng.uniforms(batch: 1, lanes: 8, seed: 7, frame: 99).asArray(Float.self)
        let crowd = Rng.uniforms(batch: 64, lanes: 8, seed: 7, frame: 99).asArray(Float.self)
        XCTAssertEqual(Array(crowd[0..<8]), solo,
                       "world 0's draw changed with batch size — batch invariance is gone")
    }
}
