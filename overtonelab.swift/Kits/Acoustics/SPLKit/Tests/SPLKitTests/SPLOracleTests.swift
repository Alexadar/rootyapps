import Testing
import Foundation
@testable import SPLKit

/// Oracles (external, cited) — Everest & Pohlmann, *Master Handbook of Acoustics*:
///  • Inverse-square law: doubling distance drops SPL by 6.02 dB.
///  • Incoherent summation: two equal sources → +3.01 dB; N coherent → +20·log₁₀(N) (+6.02 for two).
@Suite struct SPLOracle {

    @Test func inverseSquare() {
        #expect(abs(SPL.atDistance(spl1: 100, from: 1, to: 2) - 93.9794) < 1e-3)   // −6.02 dB
        #expect(abs(SPL.atDistance(spl1: 100, from: 1, to: 10) - 80) < 1e-3)       // −20 dB per decade
        // Halving distance gains 6 dB.
        #expect(abs(SPL.atDistance(spl1: 94, from: 2, to: 1) - 100.021) < 1e-2)
    }

    @Test func summation() {
        #expect(abs(SPL.sumIncoherent([90, 90]) - 93.0103) < 1e-3)   // two equal, incoherent
        #expect(abs(SPL.sumIncoherent([90, 80]) - 90.4139) < 1e-3)   // 10 dB down adds ~0.4
        #expect(abs(SPL.sumCoherent(level: 90, count: 2) - 96.0206) < 1e-3)  // two equal, coherent
    }

    @Test func guards() {
        #expect(SPL.sumIncoherent([]) == 0)
        #expect(SPL.atDistance(spl1: 100, from: 0, to: 2) == 100)
    }
}
