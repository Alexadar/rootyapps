import Testing
import Foundation
@testable import GaugeKit

// Oracle = NBS Handbook 100 §2.1 (US Government, public domain).  oracle-backed.
/// ORACLES:
///  • PUBLISHED — NBS Handbook 100 §2.1, "General Use of the American Wire Gage", verbatim:
///    "the diameter of No. 0000 is defined as 0.4600 inch and of No. 36 as 0.0050 inch. There are
///    38 sizes between ... the ratio of any diameter to the diameter of the next larger gage
///    number = 39th-root(92) = 1.122 932 2."
///    https://nvlpubs.nist.gov/nistpubs/Legacy/hb/nbshandbook100.pdf — retrieved 2026-07-29, HTTP 200.
///  • PUBLISHED — the same section's derived constants: the square of the ratio is 1.2610, and its
///    sixth power is 2.0050 ("every three gage numbers ... the cross section are doubled or halved").
///  • IDENTITY  — the two anchors are DEFINED, so the formula must return them exactly.
///  • INVARIANT — diameter decreases monotonically as the gage number rises.
///
/// MODEL CAVEAT: dimension only. Ampacity, conductor sizing, voltage drop and box fill are out of
/// scope by decision — see `docs/storypole_oracle_gate_2026-07-29.md` §5.
@Suite("AWG — oracle-backed")
struct AWGOracleTests {

    static let source = """
        NBS Handbook 100, Copper Wire Tables, §2.1; \
        https://nvlpubs.nist.gov/nistpubs/Legacy/hb/nbshandbook100.pdf \
        (US Government work, public domain); retrieved 2026-07-29.
        """

    @Test("the citation names a document and a URI")
    func citationIsComplete() {
        #expect(Self.source.contains("http"))
        #expect(Self.source.contains("Handbook 100"))
    }

    // MARK: - PUBLISHED

    /// HB 100 §2.1 prints the ratio as 1.122 932 2.
    @Test("the ratio is the 39th root of 92, printed as 1.1229322")
    func publishedRatio() {
        #expect(abs(AWG.ratio - 1.1229322) < 5e-8, "got \(AWG.ratio)")
        #expect(abs(pow(92.0, 1.0 / 39.0) - AWG.ratio) < 1e-15, "the ratio must BE the 39th root of 92")
    }

    /// "The square of this ratio = 1.2610 ... The sixth power of the ratio ... = 2.0050."
    @Test("the derived constants HB 100 prints alongside it")
    func publishedDerivedConstants() {
        #expect(abs(AWG.ratio * AWG.ratio - 1.2610) < 5e-5, "square of the ratio")
        #expect(abs(pow(AWG.ratio, 6) - 2.0050) < 5e-5, "sixth power of the ratio")
    }

    /// The two defining anchors. These are definitions, so tolerance is at machine precision.
    @Test("the two defined anchors reproduce exactly")
    func definedAnchors() {
        #expect(abs(AWG.diameterInch(gage: 36) - 0.0050) < 1e-15, "No. 36 is DEFINED as 0.0050 in")
        #expect(abs(AWG.diameterInch(gage: -3) - 0.4600) < 1e-12, "No. 0000 is DEFINED as 0.4600 in")
    }

    /// "There are 38 sizes between" the two anchors — 36 and −3 are 39 steps apart.
    @Test("there are 38 sizes between the anchors")
    func thirtyEightSizesBetween() {
        let steps = 36 - (-3)
        #expect(steps == 39, "39 ratio steps means 38 intermediate sizes")
        #expect(AWG.definedRange == -3...36)
        // And the ratio raised to those 39 steps spans the two anchors.
        #expect(abs(pow(AWG.ratio, 39) - 92.0) < 1e-9)
    }

    /// "every three gage numbers the resistance and mass per unit length and also the cross
    /// section are doubled or halved."
    @Test("cross-section halves every three gage numbers, as the Handbook states")
    func crossSectionHalvesEveryThree() {
        for n in 0...30 {
            let a = AWG.areaCircularMils(gage: n)
            let b = AWG.areaCircularMils(gage: n + 3)
            #expect(abs(a / b - 2.0) < 0.006, "gage \(n) -> \(n+3) area ratio \(a / b), HB100 says ~2")
        }
    }

    // MARK: - IDENTITY / INVARIANT

    @Test("diameter decreases as the gage number rises")
    func monotonic() {
        for n in AWG.definedRange.lowerBound..<AWG.definedRange.upperBound {
            #expect(AWG.diameterInch(gage: n) > AWG.diameterInch(gage: n + 1),
                    "gage \(n) must be thicker than \(n + 1)")
        }
    }

    @Test("millimetres use the exact 25.4 factor")
    func millimetres() {
        for n in [0, 10, 20, 36] {
            #expect(abs(AWG.diameterMillimetres(gage: n) - AWG.diameterInch(gage: n) * 25.4) < 1e-15)
        }
    }

    @Test("circular mils is the square of the diameter in mils, as the Handbook defines it")
    func circularMils() {
        for n in [0, 10, 18] {
            let mils = AWG.diameterInch(gage: n) * 1000
            #expect(abs(AWG.areaCircularMils(gage: n) - mils * mils) < 1e-9)
        }
        // Widely reprinted reference values, as a transcription cross-check on the formula.
        #expect(abs(AWG.diameterInch(gage: 0) - 0.3249) < 5e-5, "0 AWG ~ 0.3249 in")
        #expect(abs(AWG.diameterInch(gage: 10) - 0.1019) < 5e-5, "10 AWG ~ 0.1019 in")
        #expect(abs(AWG.diameterInch(gage: 12) - 0.0808) < 5e-5, "12 AWG ~ 0.0808 in")
    }

    @Test("true area is pi d squared over four, not circular mils")
    func squareInches() {
        let d = AWG.diameterInch(gage: 12)
        #expect(abs(AWG.areaSquareInches(gage: 12) - .pi * d * d / 4) < 1e-15)
        #expect(AWG.areaSquareInches(gage: 12) < AWG.areaCircularMils(gage: 12),
                "the two area conventions are not interchangeable")
    }

    @Test("gage names use the zero convention")
    func names() {
        #expect(AWG.name(gage: 12) == "12 AWG")
        #expect(AWG.name(gage: 0) == "0 AWG")
        #expect(AWG.name(gage: -3) == "0000 AWG")
    }
}
