import Testing
import Foundation
@testable import FramingKit

/// Calc #5 — stairs.
///
/// ORACLES:
///  • PUBLISHED code limits — IRC 2021 R311.7: max riser 7¾", min tread 10", headroom 6'-8".
///    (Viewrail 2021 IRC visual interpretation; buildingcodetrainer.com/residential-stair-code)
///  • PUBLISHED worked example — 108" total rise → 14 risers @ 7.71", 13 treads @ 10", run 130",
///    stringer √(108²+130²) = 169". (FIRGELLI stair calculator worked example; geometry = Pythagoras.)
@Suite struct StairsOracle {

    @Test func ircLimitsArePublishedValues() {
        #expect(StairCode.irc2021.maxRiser == 7.75)     // IRC R311.7.5.1
        #expect(StairCode.irc2021.minTread == 10)       // IRC R311.7.5.2
        #expect(StairCode.irc2021.minHeadroom == 80)    // IRC R311.7.2 (6'-8")
        #expect(StairCode.ibc.maxRiser == 7.0)          // IBC commercial
        #expect(StairCode.ibc.minTread == 11)
    }

    @Test func workedExample108() {
        let r = Stairs.solve(totalRise: 108, treadDepth: 10, idealRiser: 7.5, code: .irc2021)
        #expect(r.risers == 14)                                  // 108/7.5 = 14.4 → 14
        #expect(abs(r.riserHeight - 7.714285714) < 1e-6)         // 108/14
        #expect(r.treads == 13)
        #expect(abs(r.totalRun - 130) < 1e-9)                    // 13 × 10
        #expect(abs(r.stringerLength - 169.0088755) < 1e-4)      // √28564 ≈ 169.0
        #expect(r.riserOK)                                       // 7.714 ≤ 7.75 ✓
        #expect(r.treadOK)                                       // 10 ≥ 10 ✓
    }

    @Test func codeViolationsAreFlagged() {
        // Tread too shallow: 9" < IRC 10" minimum.
        let shallow = Stairs.solve(totalRise: 108, treadDepth: 9, idealRiser: 7.5)
        #expect(!shallow.treadOK)
        // Riser too tall: force few risers so each exceeds 7.75".
        let steep = Stairs.solve(totalRise: 108, treadDepth: 10, idealRiser: 9.0)  // 108/9=12 risers → 9"
        #expect(steep.risers == 12)
        #expect(abs(steep.riserHeight - 9.0) < 1e-9)
        #expect(!steep.riserOK)                                  // 9" > 7.75"
    }

    @Test func headroomCheck() {
        // IRC R311.7.2: minimum 6'-8" (80") headroom.
        #expect(Stairs.solve(totalRise: 108, headroomIn: 84).headroomOK)
        #expect(!Stairs.solve(totalRise: 108, headroomIn: 76).headroomOK)   // 76" < 80"
        #expect(Stairs.solve(totalRise: 108, headroomIn: 80).headroomOK)    // exactly 80"
    }

    @Test func blondelComfort() {
        // 2R + T for the 108" solution = 2·7.714 + 10 = 25.43" (within the 24–25" comfort band-ish).
        #expect(abs(Stairs.blondel(riser: 7.714285714, tread: 10) - 25.42857143) < 1e-6)
    }
}
