import Testing
import Foundation
@testable import PipeKit

/// Calc #15 — pipe weight from OD, wall and density.
///
/// ORACLES:
///  • IDENTITY — the pipefitter's published steel rule **lb/ft = 10.68 · (OD − t) · t** falls straight
///    out of the hollow-cylinder volume: `π · (OD − t) · t · 12 in/ft · 0.2833 lb/in³ = 10.680`.
///    Asserting that our formula reproduces the printed constant is an identity oracle for a number
///    the trade tabulates — and it means no table has to ship.
///  • PUBLISHED — two ASME B36.10M schedule-40 carbon-steel weights as an independent cross-check:
///    2″ (OD 2.375″, wall 0.154″) = 3.65 lb/ft and 4″ (OD 4.500″, wall 0.237″) = 10.79 lb/ft.
///    These are *test* values, not shipped data — the app asks the user for OD, wall and density.
///  • NOT oracle-backed — the density itself. It is a user-entered material property
///    (carbon steel ≈ 0.2833 lb/in³, copper ≈ 0.323, PVC ≈ 0.051).
@Suite struct PipeWeightOracle {

    /// Density that makes the published 10.68 constant come out exactly — carbon steel.
    private static let steelLbPerIn3 = 0.2833

    @Test func reproducesThePublished1068Constant() {
        // oracle: published steel rule lb/ft = 10.68 · (OD − t) · t
        #expect(abs(Double.pi * 12 * Self.steelLbPerIn3 - 10.68) < 0.0005)
        for (od, t) in [(4.5, 0.237), (2.375, 0.154), (6.625, 0.280), (1.05, 0.113)] {
            let ours = PipeWeight.weightLbPerFt(odIn: od, wallIn: t, densityLbPerIn3: Self.steelLbPerIn3)
            #expect(abs(ours - 10.68 * (od - t) * t) < 0.002)         // identity, to the constant's precision
        }
    }

    @Test func publishedScheduleFortyWeights() {
        // oracle: ASME B36.10M schedule 40 carbon steel, published lb/ft (2-decimal tables)
        let two = PipeWeight.weightLbPerFt(odIn: 2.375, wallIn: 0.154, densityLbPerIn3: Self.steelLbPerIn3)
        #expect(abs(two - 3.65) < 0.01)
        let four = PipeWeight.weightLbPerFt(odIn: 4.5, wallIn: 0.237, densityLbPerIn3: Self.steelLbPerIn3)
        #expect(abs(four - 10.79) < 0.01)
        let six = PipeWeight.weightLbPerFt(odIn: 6.625, wallIn: 0.280, densityLbPerIn3: Self.steelLbPerIn3)
        #expect(abs(six - 18.97) < 0.02)
    }

    /// Identity anchor — the compact `π·(OD−t)·t` form must equal the textbook annulus it came from.
    @Test func wallAreaEqualsAnnulus() {
        for (od, t) in [(4.5, 0.237), (2.375, 0.154), (10.75, 0.365)] {
            let id = PipeWeight.idIn(odIn: od, wallIn: t)
            let annulus = Double.pi / 4 * (od * od - id * id)
            #expect(abs(PipeWeight.wallAreaIn2(odIn: od, wallIn: t) - annulus) < 1e-9)
        }
        #expect(abs(PipeWeight.idIn(odIn: 4.5, wallIn: 0.237) - 4.026) < 1e-9)   // published Sch-40 4" ID
    }

    @Test func weightScalesWithLength() {
        let perFt = PipeWeight.weightLbPerFt(odIn: 4.5, wallIn: 0.237, densityLbPerIn3: Self.steelLbPerIn3)
        #expect(abs(PipeWeight.weightLb(lengthFt: 21, odIn: 4.5, wallIn: 0.237,
                                        densityLbPerIn3: Self.steelLbPerIn3) - perFt * 21) < 1e-9)
        #expect(PipeWeight.weightLb(lengthFt: 0, odIn: 4.5, wallIn: 0.237,
                                    densityLbPerIn3: Self.steelLbPerIn3) == 0)
    }

    @Test func guardsNoCrash() {
        #expect(PipeWeight.wallAreaIn2(odIn: 0, wallIn: 0.237) == 0)      // no pipe → 0
        #expect(PipeWeight.wallAreaIn2(odIn: 4.5, wallIn: 0) == 0)        // no wall → 0
        #expect(PipeWeight.wallAreaIn2(odIn: 4.5, wallIn: -0.2) == 0)     // negative wall → 0
        #expect(PipeWeight.wallAreaIn2(odIn: 4.5, wallIn: 2.25) == 0)     // wall closes the bore → 0
        #expect(PipeWeight.wallAreaIn2(odIn: 4.5, wallIn: 9) == 0)        // wall thicker than the pipe → 0
        #expect(PipeWeight.idIn(odIn: 1.0, wallIn: 0.6) == 0)             // solid bar → 0, not negative
    }
}
