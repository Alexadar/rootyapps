import Testing
import Foundation
@testable import BernoulliKit

// Oracle = published acoustic pipe formulas + invariants. Model-caveat app.
@Suite("Air-column resonance")
struct PipesTests {
    @Test func openPipeFundamental() {
        // 0.5 m open pipe: f1 = 343/(2·0.5) = 343 Hz.
        #expect(abs(Pipes.openPipeHz(lengthM: 0.5, harmonic: 1) - 343) < 1e-9)
    }
    @Test func closedPipeIsOctaveLowerAndOddOnly() {
        // Closed pipe fundamental = half the open-pipe fundamental (an octave down).
        let openF = Pipes.openPipeHz(lengthM: 1.0, harmonic: 1)
        let closedF = Pipes.closedPipeHz(lengthM: 1.0, harmonic: 1)
        #expect(abs(closedF - openF / 2) < 1e-9)
        // 2nd resonance of a closed pipe is the 3rd harmonic (odd only).
        #expect(abs(Pipes.closedPipeHz(lengthM: 1.0, harmonic: 2) - 3 * closedF) < 1e-9)
    }
    @Test func endCorrectionRaisesEffectiveLength() {
        #expect(Pipes.endCorrectionM(radiusM: 0.02, flanged: true) > Pipes.endCorrectionM(radiusM: 0.02, flanged: false))
        #expect(abs(Pipes.endCorrectionM(radiusM: 0.02, flanged: false) - 0.6133 * 0.02) < 1e-12)
    }
}
