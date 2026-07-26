import Testing
import Foundation
@testable import FramingKit

/// Calc #3 — rafters.
///
/// ORACLE (published): the numbers printed on a physical framing-square rafter table —
/// "common rafter length per foot of run" and "hip or valley … per foot of run".
/// Verified values (InspectAPedia "Framing Square Rafter Table"; NAVEDTRA 14044):
///   common: 3→12.37, 6→13.42, 7→13.89, 18→21.63    hip/valley: 6→18.00
/// The square rounds to 1/100"; we match to ±0.005.
@Suite struct RafterOracle {

    @Test func commonPerFootRun_framingSquareTable() {
        #expect(abs(Rafter.commonPerFootRun(rise: 3) - 12.37) < 0.005)   // published table
        #expect(abs(Rafter.commonPerFootRun(rise: 6) - 13.42) < 0.005)   // published table
        #expect(abs(Rafter.commonPerFootRun(rise: 7) - 13.89) < 0.005)   // published table
        #expect(abs(Rafter.commonPerFootRun(rise: 18) - 21.63) < 0.005)  // published table
    }

    @Test func hipValleyPerFootRun_framingSquareTable() {
        #expect(abs(Rafter.hipValleyPerFootRun(rise: 6) - 18.00) < 0.005) // published table
        #expect(abs(Rafter.hipUnitRun - 16.9705627) < 1e-6)               // 12√2 (identity)
    }

    @Test func totalLengths() {
        // 6/12 roof, 10 ft run: common line length = 13.4164 × 10 = 134.164"
        #expect(abs(Rafter.commonLength(rise: 6, runFeet: 10) - 134.1640786) < 1e-4)
        // hip for the same: 18.0 × 10 = 180.0"
        #expect(abs(Rafter.hipValleyLength(rise: 6, commonRunFeet: 10) - 180.0) < 1e-4)
    }

    @Test func cutAngles() {
        // Plumb cut = pitch angle: 6/12 → 26.565°, complement (level) = 63.435°.
        #expect(abs(Rafter.plumbCutDegrees(rise: 6) - 26.5650512) < 1e-6)
        #expect(abs(Rafter.levelCutDegrees(rise: 6) - 63.4349488) < 1e-6)
        #expect(abs(Rafter.plumbCutDegrees(rise: 12) - 45.0) < 1e-9)
    }

    @Test func actualCutWithRidgeAndOverhang() {
        // 6/12, 12 ft run, 1½" ridge, 12" overhang. Slope factor = √180/12 = 1.11803399.
        // Exact geometry (no rounded intermediates):
        //   line = 12 ft × √180 in/ft   = 160.9968943"
        //   − ridge (0.75 × 1.1180340)  =   0.8385255"
        //   + tail  (12   × 1.1180340)  =  13.4164079"
        //   actual                      = 173.5747767"
        // Equivalently the closed form (144 − 0.75 + 12) × √180/12 = 155.25 × 1.11803399.
        #expect(abs(Rafter.slopeFactor(rise: 6) - 1.1180340) < 1e-6)
        #expect(abs(Rafter.ridgeDeductionIn(rise: 6, ridgeThicknessIn: 1.5) - 0.8385255) < 1e-6)
        #expect(abs(Rafter.overhangAlongIn(rise: 6, overhangIn: 12) - 13.4164079) < 1e-6)
        #expect(abs(Rafter.actualLength(rise: 6, runFeet: 12, ridgeThicknessIn: 1.5, overhangIn: 12) - 173.5747767) < 1e-4)
        // Identity anchor: actual == line − ridge + tail, independent of the constant above.
        let identity = Rafter.commonLength(rise: 6, runFeet: 12)
            - Rafter.ridgeDeductionIn(rise: 6, ridgeThicknessIn: 1.5)
            + Rafter.overhangAlongIn(rise: 6, overhangIn: 12)
        #expect(abs(Rafter.actualLength(rise: 6, runFeet: 12, ridgeThicknessIn: 1.5, overhangIn: 12) - identity) < 1e-9)
        // Closed form via 155.25" horizontal × slope factor.
        #expect(abs(Rafter.actualLength(rise: 6, runFeet: 12, ridgeThicknessIn: 1.5, overhangIn: 12)
                    - 155.25 * Rafter.slopeFactor(rise: 6)) < 1e-9)
    }

    @Test func jackRafters() {
        // 6/12, 16" o.c.: common difference = 16 × 13.4164/12 = 17.888"  (identity)
        #expect(abs(Rafter.jackCommonDifference(rise: 6, spacingInches: 16) - 17.8885438) < 1e-6)
        // successive jacks step down by exactly the common difference
        let d = Rafter.jackCommonDifference(rise: 6, spacingInches: 16)
        let j1 = Rafter.jackLength(rise: 6, longestRunFeet: 10, spacingInches: 16, index: 1)
        let j2 = Rafter.jackLength(rise: 6, longestRunFeet: 10, spacingInches: 16, index: 2)
        #expect(abs((j1 - j2) - d) < 1e-9)
    }
}
