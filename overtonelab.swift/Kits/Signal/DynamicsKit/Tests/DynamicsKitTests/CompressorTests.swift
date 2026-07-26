import Testing
import Foundation
@testable import DynamicsKit

// Oracle = Giannoulis, Massberg & Reiss, "Digital Dynamic Range Compressor Design" (JAES 2012):
// the log-domain gain computer GR=(x−T)(1−1/R) above a hard knee, the soft-knee interpolation,
// and the one-pole time-constant relations (τ = t/ln9; 63.2 % at one τ).
@Suite("Compressor / dynamics")
struct CompressorTests {
    @Test func hardKneeGainReduction() {
        // input −10, threshold −20, ratio 4, hard knee → GR = 10·(1−1/4) = 7.5 dB.
        #expect(abs(Compressor.gainReductionDB(inputDB: -10, thresholdDB: -20, ratio: 4, kneeDB: 0) - 7.5) < 1e-12)
        // Below threshold: no reduction.
        #expect(Compressor.gainReductionDB(inputDB: -25, thresholdDB: -20, ratio: 4, kneeDB: 0) == 0)
        // At threshold (hard knee): no reduction.
        #expect(abs(Compressor.gainReductionDB(inputDB: -20, thresholdDB: -20, ratio: 4, kneeDB: 0)) < 1e-12)
    }

    @Test func wellAboveSoftKneeMatchesHard() {
        // −10 is 10 dB over threshold, far outside a 6 dB knee → same 7.5 dB and ratio 4.
        #expect(abs(Compressor.gainReductionDB(inputDB: -10, thresholdDB: -20, ratio: 4, kneeDB: 6) - 7.5) < 1e-9)
        #expect(abs(Compressor.effectiveRatio(inputDB: -10, thresholdDB: -20, ratio: 4, kneeDB: 6) - 4) < 1e-9)
    }

    @Test func softKneeIsContinuousAtEdges() {
        // Lower knee edge (x = T − W/2): reduction starts from zero.
        #expect(abs(Compressor.gainReductionDB(inputDB: -23, thresholdDB: -20, ratio: 4, kneeDB: 6)) < 1e-9)
        // Upper knee edge (x = T + W/2 = −17): matches the hard formula (x−T)(1−1/R) = 3·0.75 = 2.25.
        #expect(abs(Compressor.gainReductionDB(inputDB: -17, thresholdDB: -20, ratio: 4, kneeDB: 6) - 2.25) < 1e-9)
    }

    @Test func outputAddsMakeup() {
        let y = Compressor.computerOutputDB(inputDB: -10, thresholdDB: -20, ratio: 4, kneeDB: 0)   // T + d/R = −17.5
        #expect(abs(Compressor.outputLevelDB(inputDB: -10, thresholdDB: -20, ratio: 4, kneeDB: 0, makeupDB: 6) - (y + 6)) < 1e-12)
        #expect(abs(y - (-17.5)) < 1e-12)
    }

    @Test func timeConstantRelations() {
        #expect(abs(Compressor.timeConstantMs(riseTimeMs: 10) - 10 / log(9)) < 1e-12)   // ≈ 4.551 ms
        // 63.2 % reached at one time constant.
        let rt = 10.0, tau = Compressor.timeConstantMs(riseTimeMs: rt)
        #expect(abs(Compressor.percentReached(afterMs: tau, riseTimeMs: rt) - (1 - exp(-1))) < 1e-12)
        // One-pole coefficient is in (0,1) and rises toward 1 for longer times.
        let a = Compressor.onePoleCoeff(riseTimeMs: 10, fs: 48000)
        #expect(a > 0 && a < 1)
        #expect(Compressor.onePoleCoeff(riseTimeMs: 100, fs: 48000) > a)
    }
}
