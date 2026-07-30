import Testing
import Foundation
import FramingKit

/// The watch stair screen has no tread-depth input, so it solves with `treadDepth: code.minTread`
/// and lets the code picker drive the tread. These are *invariant* tests of that contract — not
/// oracle values. The riser/tread limits themselves are oracle-tested inside FramingKit.
///
/// Without this, changing a code's `minTread` (or the comparison tolerance in `Stairs.solve`) would
/// silently make the watch emit a layout that fails the very code the user just selected — the exact
/// bug this contract was introduced to fix.
@Suite struct WatchStairCodeTests {

    /// Every shipped code must be self-consistent: solving at its own minimum tread passes its own
    /// tread check. If this fails, the watch is showing a non-compliant tread with no way to fix it.
    @Test func solvingAtTheCodeMinimumTreadIsCompliant() {
        for code in [StairCode.irc2021, StairCode.ibc] {
            let r = Stairs.solve(totalRise: 108, treadDepth: code.minTread, code: code)
            #expect(r.treadOK, "\(code.name): tread \(r.treadDepth)\" failed its own minimum")
            #expect(r.treadDepth == code.minTread)
        }
    }

    /// The two codes must actually differ in tread, or the picker is decorative.
    @Test func theCodePickerChangesTheLayout() {
        let irc = Stairs.solve(totalRise: 108, treadDepth: StairCode.irc2021.minTread, code: .irc2021)
        let ibc = Stairs.solve(totalRise: 108, treadDepth: StairCode.ibc.minTread, code: .ibc)
        #expect(ibc.treadDepth > irc.treadDepth)
        #expect(ibc.totalRun > irc.totalRun)      // a deeper tread must lengthen the flight
    }

    /// Regression guard for the defect itself: the Kit's default tread (10") violates IBC. This is
    /// correct Kit behaviour — `solve` never bends input to fit a code — which is precisely why the
    /// watch must pass the code's minimum instead of relying on the default.
    @Test func theKitDefaultTreadViolatesIBC() {
        let r = Stairs.solve(totalRise: 108, code: .ibc)
        #expect(!r.treadOK)
    }

    /// The riser check is independent of tread depth: rise per riser is unchanged by the picker.
    @Test func treadDepthDoesNotMoveTheRiser() {
        let a = Stairs.solve(totalRise: 108, treadDepth: 10, code: .irc2021)
        let b = Stairs.solve(totalRise: 108, treadDepth: 11, code: .irc2021)
        #expect(a.risers == b.risers)
        #expect(abs(a.riserHeight - b.riserHeight) < 1e-12)
    }
}
