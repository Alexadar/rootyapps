import Testing
import Foundation
import DimensionKit
@testable import LumberKit

// Oracle = NIST PS 20-20 §2.2, Table 3 and App. B.  oracle-backed.
/// ORACLES:
///  • PUBLISHED — PS 20-20 §2.2 board measure, with four worked cases including the definitional
///    144 in³ = 1 BF.
///  • PUBLISHED — PS 20-20 Table 3 dressed sizes: a 2x4 is 1-1/2" x 3-1/2" dry.
///  • PUBLISHED — the whole of Table 3's dry column re-derived from 25.4 mm/in under the App. B
///    §B1 half-to-even rule, so the transcription is checked against the standard's own arithmetic
///    rather than merely retyped.
///  • INVARIANT — the Kit exposes NO board-foot-to-cubic-metre conversion, because PS 20-20
///    App. B forbids it.
@Suite("Lumber — oracle-backed")
struct LumberOracleTests {

    @Test("oracle corpus integrity")
    func corpusIsCited() {
        var ids = Set<String>()
        for o in Oracles.all {
            #expect(!o.source.isEmpty, "oracle \(o.id) has no source")
            #expect(o.source.contains("http"), "oracle \(o.id) has no URI")
            #expect(o.source.contains("PS 20-20"), "oracle \(o.id) does not name the standard")
            #expect(!o.precision.isEmpty, "oracle \(o.id) has no stated precision")
            #expect(ids.insert(o.id).inserted, "duplicate oracle id \(o.id)")
            for k in o.values.keys { #expect(o.tolerances[k] != nil, "\(o.id).\(k) has no tolerance") }
        }
    }

    // MARK: - PUBLISHED: board measure

    @Test("PS 20-20 §2.2 board measure", arguments: ["bf-2x4x8", "bf-2x10x16", "bf-1x12x10"])
    func boardMeasure(id: String) {
        let o = Oracles.require(id)
        let bf = BoardFeet.exact(thicknessIn: Rational(Int64(o.inputs["thicknessIn"]!)),
                                 widthIn: Rational(Int64(o.inputs["widthIn"]!)),
                                 lengthFt: Rational(Int64(o.inputs["lengthFt"]!)))
        #expect(o.matches("boardFeet", bf.doubleValue), "\(id): got \(bf) = \(bf.doubleValue)")
    }

    @Test("a 2x4x8 is exactly 16/3 board feet, not 5.33")
    func boardFeetStayExact() {
        let bf = BoardFeet.exact(thicknessIn: Rational(2), widthIn: Rational(4), lengthFt: Rational(8))
        #expect(bf == Rational(16, 3), "got \(bf) — the point of the rational path is that this is exact")
    }

    @Test("the definition: 144 cubic inches of nominal section is one board foot")
    func oneBoardFoot() {
        let o = Oracles.require("bf-one-board-foot")
        let bf = BoardFeet.exact(thicknessIn: Rational(1), widthIn: Rational(12), lengthIn: Rational(12))
        #expect(bf == Rational(1))
        #expect(o.matches("boardFeet", bf.doubleValue))
    }

    @Test("a parcel scales linearly")
    func parcelScales() {
        let one = BoardFeet.exact(thicknessIn: Rational(2), widthIn: Rational(6), lengthFt: Rational(10))
        let fifty = BoardFeet.exact(pieces: 50, thicknessIn: Rational(2), widthIn: Rational(6), lengthFt: Rational(10))
        #expect(fifty == one * Rational(50))
        #expect(one == Rational(10), "2x6x10 is exactly 10 BF")
    }

    // MARK: - PUBLISHED: Table 3

    @Test("PS 20-20 Table 3 dressed sections",
          arguments: ["dressed-2x4-dry", "dressed-2x10-dry", "dressed-1x6-dry"])
    func dressedSections(id: String) {
        let o = Oracles.require(id)
        let section = DressedSize.section(nominalThicknessIn: Rational(Int64(o.inputs["nominalThicknessIn"]!)),
                                          nominalWidthIn: Rational(Int64(o.inputs["nominalWidthIn"]!)),
                                          seasoning: .dry)
        guard let s = section else { Issue.record("\(id): no dressed size found"); return }
        #expect(o.matches("dressedThicknessIn", s.thickness.inchesValue))
        #expect(o.matches("dressedWidthIn", s.width.inchesValue))
    }

    @Test("the row everybody knows: a 2x4 is 1-1/2\" x 3-1/2\"")
    func twoByFour() {
        let s = DressedSize.section(nominalThicknessIn: Rational(2), nominalWidthIn: Rational(4))
        #expect(s?.thickness.formatted() == "1-1/2\"")
        #expect(s?.width.formatted() == "3-1/2\"")
    }

    @Test("green lumber is dressed larger than dry")
    func greenIsLarger() {
        let o = Oracles.require("dressed-2x4-green")
        let g = DressedSize.section(nominalThicknessIn: Rational(2), nominalWidthIn: Rational(4), seasoning: .green)
        #expect(o.matches("dressedThicknessIn", g!.thickness.inchesValue))
        #expect(o.matches("dressedWidthIn", g!.width.inchesValue))
        let d = DressedSize.section(nominalThicknessIn: Rational(2), nominalWidthIn: Rational(4), seasoning: .dry)!
        #expect(d.thickness < g!.thickness, "dry lumber has shrunk below green")
    }

    /// The transcription is checked against the standard's OWN arithmetic: 25.4 mm/in rounded by
    /// App. B §B1 (half-to-even) must reproduce the millimetre column for every row.
    @Test("every Table 3 row's mm value re-derives from 25.4 mm/in under the §B1 rule")
    func millimetreColumnReDerives() {
        for row in DressedSize.table {
            let mm = (row.dryIn * Rational(254, 10)).rounded(toDenominator: 1, rule: .halfToEven).num
            #expect(Int(mm) == row.dryMM,
                    "nominal \(row.nominalIn): dressed \(row.dryIn) in -> computed \(mm) mm, table says \(row.dryMM) mm")
        }
    }

    @Test("an untabulated nominal size returns nil rather than a guess")
    func untabulatedIsNil() {
        let r = DressedSize.dressed(nominalIn: Rational(13))   // 13 is not in Table 3
        #expect(r == nil)
        #expect(DressedSize.section(nominalThicknessIn: Rational(2), nominalWidthIn: Rational(13)) == nil)
    }

    // MARK: - The refusal

    /// PS 20-20 App. B: "CAUTION: Use great care when converting board feet, based on NOMINAL
    /// cross-sectional dimensions, to cubic meters of lumber, based on DRESSED cross-sectional
    /// dimensions." So there is no such function, and this test documents the absence.
    @Test("board feet and dressed volume genuinely differ — which is why no conversion is offered")
    func theCautionIsReal() {
        let nominalBF = BoardFeet.exact(thicknessIn: Rational(2), widthIn: Rational(4), lengthFt: Rational(8))
        let dressedFt3 = BoardFeet.dressedCubicFeet(nominalThicknessIn: Rational(2),
                                                    nominalWidthIn: Rational(4),
                                                    lengthFt: Rational(8))!
        // One board foot is 1/12 ft³ of NOMINAL section. If the two agreed, a conversion would be
        // legitimate; they do not, by 34.4%.
        let nominalAsFt3 = nominalBF / Rational(12)
        #expect(dressedFt3 < nominalAsFt3, "dressed volume must be smaller than nominal")
        let fraction = DressedSize.dressedSectionFraction(nominalThicknessIn: Rational(2),
                                                          nominalWidthIn: Rational(4))!
        #expect(fraction == Rational(21, 32), "a 2x4 delivers 21/32 = 65.6% of its nominal section")
        #expect(abs(fraction.doubleValue - 0.65625) < 1e-12)
    }

    @Test("the CAUTION and the nominal disclaimer are carried verbatim for the Reference screen")
    func cautionTextIsPresent() {
        #expect(BoardFeet.cubicMetreCaution.contains("NOMINAL"))
        #expect(BoardFeet.cubicMetreCaution.contains("DRESSED"))
        #expect(BoardFeet.cubicMetreCaution.contains("PS 20-20"))
        #expect(DressedSize.nominalDisclaimer.contains("No inferences shall be drawn"))
    }
}
