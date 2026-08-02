import Testing
import Foundation
@testable import DimensionKit

/// CM-Pro dimension math on the tape: linear × linear = area, × linear = volume, ÷ drops a dimension.
/// Bare numbers stay scalar multipliers (so 10' × 3 = 30', unchanged). Oracle: geometry + CM-Pro behavior.
@Suite struct TapeDimensionScenarios {
    private func digits(_ c: inout TapeCalc, _ n: Int) { for ch in String(n) { c.digit(Int(String(ch))!) } }

    @Test func areaFromTwoLengths() {
        var c = TapeCalc()
        digits(&c, 10); c.feetKey(); c.setOp(.mul)
        digits(&c, 8); c.feetKey(); c.equals()
        #expect(c.display == "80 sq ft")                 // 10' × 8'
        #expect(c.currentDimension == .square)
        #expect(c.areaFt2.map { abs($0 - 80) < 1e-9 } == true)
    }

    @Test func volumeFromThreeLengths() {
        var c = TapeCalc()
        digits(&c, 10); c.feetKey(); c.setOp(.mul)
        digits(&c, 8); c.feetKey(); c.setOp(.mul)
        digits(&c, 4); c.inchKey(); c.equals()
        #expect(c.display == "26.67 cu ft")              // 80 sq ft × 4" = 26.67 ft³
        #expect(c.volumeFt3.map { abs($0 - 26.6667) < 1e-3 } == true)
    }

    @Test func areaDividedByLengthGivesLength() {
        var c = TapeCalc()
        digits(&c, 10); c.feetKey(); c.setOp(.mul)
        digits(&c, 10); c.feetKey(); c.setOp(.div)
        digits(&c, 10); c.feetKey(); c.equals()
        #expect(c.display == "10'")                      // 100 sq ft ÷ 10' = 10'
        #expect(c.currentDimension == .linear)
    }

    @Test func lengthOverLengthIsRatio() {
        var c = TapeCalc()
        digits(&c, 10); c.feetKey(); c.setOp(.div)
        digits(&c, 2); c.feetKey(); digits(&c, 6); c.inchKey(); c.equals()
        #expect(c.display == "4")                        // 10' ÷ 2'6" = 4 (dimensionless)
        #expect(c.currentDimension == .scalar)
    }

    // Guard: bare-number scalar behavior is UNCHANGED (no accidental area).
    @Test func bareNumberStaysScalarMultiply() {
        var c = TapeCalc()
        digits(&c, 10); c.feetKey(); c.setOp(.mul)
        digits(&c, 3); c.equals()
        #expect(c.display == "30'")                      // 10' × 3 = 30' (not 30 sq-in)
        #expect(c.currentDimension == .linear)
    }
}
