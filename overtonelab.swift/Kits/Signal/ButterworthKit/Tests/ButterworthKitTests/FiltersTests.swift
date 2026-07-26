import Testing
import Foundation
@testable import ButterworthKit

// Oracle = published Butterworth response properties (−3 dB at cutoff, −20n dB/decade, maximally flat).
@Suite("Butterworth / Linkwitz-Riley")
struct FiltersTests {
    @Test func minus3dBAtCutoffAnyOrder() {
        for n in 1...8 {
            #expect(abs(Filters.butterworthDB(order: n, ratio: 1) - (-3.0103)) < 1e-3)   // 20·log10(1/√2)
        }
    }
    @Test func rolloffIs20nPerDecade() {
        // Asymptotic slope: from one decade to the next above cutoff, an nth-order Butterworth
        // loses ≈ 20n dB. (At a single decade it's only ~−20.04n; the slope is the exact claim.)
        for n in 1...4 {
            let slope = Filters.butterworthDB(order: n, ratio: 100) - Filters.butterworthDB(order: n, ratio: 10)
            #expect(abs(slope - Double(-20 * n)) < 0.05)
        }
    }
    @Test func maximallyFlatAtDC() {
        #expect(abs(Filters.butterworthMag(order: 4, ratio: 0) - 1) < 1e-12)
    }
    @Test func linkwitzRileyMinus6AtCrossover() {
        #expect(abs(Filters.linkwitzRileyDB(butterworthOrder: 2, ratio: 1) - (-6.0206)) < 1e-3)
    }
}
