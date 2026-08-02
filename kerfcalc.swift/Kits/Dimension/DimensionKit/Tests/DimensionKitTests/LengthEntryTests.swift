import Testing
import Foundation
@testable import DimensionKit

/// Field ↔ feet-inch conversion (the tool dimension fields) + keypad preload.
@Suite struct LengthEntryTests {

    @Test func formatFeetUnit() {
        #expect(LengthEntry.text(12, unit: .foot) == "12'")
        #expect(LengthEntry.text(8.375, unit: .foot) == "8' 4-1/2\"")   // 8.375 ft = 100.5" = 8'4½"
        #expect(LengthEntry.text(0.5, unit: .foot) == "6\"")            // half a foot
    }

    @Test func formatInchUnit() {
        #expect(LengthEntry.text(108, unit: .inch) == "9'")             // 108" = 9'
        #expect(LengthEntry.text(4, unit: .inch) == "4\"")
        #expect(LengthEntry.text(30, unit: .inch) == "2' 6\"")
    }

    @Test func parseIntoFeetUnit() {
        #expect(LengthEntry.value(fromText: "8' 4 1/2\"", unit: .foot).map { abs($0 - 8.375) < 1e-9 } == true)
        #expect(LengthEntry.value(fromText: "12'", unit: .foot).map { abs($0 - 12) < 1e-9 } == true)
        #expect(LengthEntry.value(fromText: "garbage", unit: .foot) == nil)
    }

    @Test func parseIntoInchUnit() {
        #expect(LengthEntry.value(fromText: "9'", unit: .inch).map { abs($0 - 108) < 1e-9 } == true)
        #expect(LengthEntry.value(fromText: "2' 6\"", unit: .inch).map { abs($0 - 30) < 1e-9 } == true)
    }

    @Test func roundTrip() {
        for (v, u) in [(8.375, LengthUnit.foot), (12.0, .foot), (108.0, .inch), (4.0, .inch)] {
            let t = LengthEntry.text(v, unit: u)
            let back = LengthEntry.value(fromText: t, unit: u)!
            #expect(abs(back - v) < 1e-6, "round-trip \(v) \(u)")
        }
    }

    @Test func keypadPreloadThenReplace() {
        var c = TapeCalc()
        c.preload(FeetInch(feet: 8, inches: 4, num: 1, den: 2))         // shows 8'4½"
        #expect(c.display == "8' 4-1/2\"")
        c.digit(9)                                                       // first digit replaces
        c.inchKey()
        #expect(c.display == "9\"")
    }
}
