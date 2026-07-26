import Testing
import Foundation
@testable import InterferenceKit

// Oracle = exact interference geometry (standard SBIR & comb-filter formulas): a boundary at
// distance d nulls at (2k−1)·c/(4d); two sources Δ apart null at (2k−1)·c/(2Δ), spaced c/Δ.
@Suite("Interference — SBIR & comb")
struct CombTests {
    let c = 343.0

    @Test func boundaryFirstNotchWorkedValue() {
        // d = 0.6 m → first notch = c/(4d) = 343/2.4 = 142.9167 Hz.
        let notches = Comb.boundaryNotches(distanceM: 0.6, speed: c)
        #expect(abs(notches[0] - 142.91667) < 1e-4)
        #expect(abs(notches[1] - 3 * 142.91667) < 1e-3)   // odd harmonics
        #expect(abs(Comb.boundaryFirstPeak(distanceM: 0.6, speed: c) - 285.83333) < 1e-4)  // c/(2d)
    }

    @Test func distanceRoundTrips() {
        let f = Comb.boundaryNotches(distanceM: 0.6, speed: c)[0]
        #expect(abs(Comb.distanceForFirstNotchAbove(targetHz: f, speed: c) - 0.6) < 1e-9)
    }

    @Test func combNullsAndSpacing() {
        // Δ = 1 m → first null c/(2Δ) = 171.5 Hz, spacing c/Δ = 343 Hz.
        #expect(abs(Comb.combFirstNull(pathDiffM: 1.0, speed: c) - 171.5) < 1e-9)
        #expect(abs(Comb.combSpacing(pathDiffM: 1.0, speed: c) - 343) < 1e-9)
        let nulls = Comb.combNulls(pathDiffM: 1.0, speed: c, count: 3)
        #expect(abs(nulls[0] - 171.5) < 1e-9)
        #expect(abs(nulls[1] - 514.5) < 1e-9)
        #expect(abs(nulls[2] - 857.5) < 1e-9)
    }

    @Test func reflectionDepthAndGain() {
        // Full reflection: peak = +6.02 dB, null = −∞.
        #expect(abs(Comb.peakGainDB(reflectionGainDB: 0) - 6.0206) < 1e-3)
        #expect(Comb.nullDepthDB(reflectionGainDB: 0) == -Double.infinity)
        // −6.02 dB reflection (r = 0.5): peak +3.52 dB, null −6.02 dB.
        #expect(abs(Comb.peakGainDB(reflectionGainDB: -6.0206) - 3.5218) < 1e-3)
        #expect(abs(Comb.nullDepthDB(reflectionGainDB: -6.0206) - (-6.0206)) < 1e-3)
    }

    @Test func delayPathRoundTrip() {
        #expect(abs(Comb.delayMs(pathDiffM: 1.0, speed: c) - 1000.0 / 343.0) < 1e-9)
        #expect(abs(Comb.pathFromDelay(ms: Comb.delayMs(pathDiffM: 2.5, speed: c), speed: c) - 2.5) < 1e-12)
        // first null also equals 1/(2τ) with τ in seconds.
        let tau = Comb.delayMs(pathDiffM: 1.0, speed: c) / 1000
        #expect(abs(Comb.combFirstNull(pathDiffM: 1.0, speed: c) - 1 / (2 * tau)) < 1e-6)
    }
}
