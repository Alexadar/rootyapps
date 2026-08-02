import Testing
import Foundation
@testable import CommaKit

// IDENTITY: definitional tuning math (self-evident closed forms).
@Suite("Tuning identities")
struct TuningTests {
    @Test func edo12() {
        let s = Tuning.edo(12)
        #expect(s.count == 12)
        for (i, c) in s.enumerated() { #expect(abs(c - Double(i + 1) * 100) < 1e-9) }
    }
    @Test func namedIntervals() {
        #expect(abs(Tuning.justFifthCents - 701.955) < 0.001)
        #expect(abs(Tuning.quarterCommaMeantoneFifthCents - 696.578) < 0.001)
        #expect(abs(Tuning.syntonicCommaCents - 21.506) < 0.001)
        #expect(abs(Tuning.pythagoreanCommaCents - 23.460) < 0.001)
    }
    @Test func parseInlineSCL() {
        let scl = """
        ! test.scl
        !
        an inline scale
         3
        !
         204.0
         5/4
         2/1
        """
        let c = Tuning.parseSCL(scl)
        #expect(c != nil)
        #expect(c?.count == 3)
        #expect(abs((c?[0] ?? 0) - 204.0) < 1e-9)
        #expect(abs((c?[1] ?? 0) - Tuning.cents(ratio: 1.25)) < 1e-9)   // 386.314
        #expect(abs((c?[2] ?? 0) - 1200.0) < 1e-9)                       // 2/1 octave
    }
}
