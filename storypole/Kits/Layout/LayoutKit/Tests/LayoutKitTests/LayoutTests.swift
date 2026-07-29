import Testing
import Foundation
import DimensionKit
@testable import LayoutKit

// Oracle = exact rational division (identity) + USDA Agriculture Handbook 73 for the o.c. values.  identity/invariant.
/// ORACLES:
///  • IDENTITY/INVARIANT — the mark arithmetic. There is NO published authority for it and none is
///    claimed (`docs/storypole_oracle_gate_2026-07-29.md` §4, decided 2026-07-29). It is proved by
///    invariants: marks strictly increase, the first is 0, the last is the span, there are
///    parts+1 of them, and THE BAYS SUM TO THE SPAN EXACTLY.
///  • PUBLISHED — the 16" and 24" on-center values, USDA Agriculture Handbook 73,
///    "Wood-Frame House Construction" (US Government work, public domain):
///    "joists ... spaced 16 inches on center"; "nor exceed 24 inches on center";
///    "2- by 4-inch studs spaced 16 inches on center".
///  • NOT PUBLISHED — 19.2" o.c. is absent from AH-73. It is 96/5, the 8-foot sheet in five bays,
///    and the Kit labels it as derived.
@Suite("Layout — equal spacing and on-center")
struct LayoutTests {

    // MARK: - EqualSpacing: INVARIANT

    @Test("marks divide the span exactly — bays sum back to the span")
    func baysSumToSpanExactly() {
        for parts in 2...24 {
            for sixteenths in [997, 1000, 1234, 62 * 16 + 4] {     // includes 62 1/4"
                let span = FeetInch(inches: Rational(Int64(sixteenths), 16))
                let marks = EqualSpacing.marks(span: span, parts: parts)
                #expect(marks.count == parts + 1, "expected \(parts + 1) marks")
                #expect(marks.first == .zero, "the first mark is the end of the board")
                #expect(marks.last == span, "the last mark is the span exactly")

                var total = FeetInch.zero
                for i in 1..<marks.count { total = total + (marks[i] - marks[i - 1]) }
                #expect(total == span, "bays summed to \(total), span is \(span) — must be exact")
            }
        }
    }

    @Test("marks strictly increase and every bay is the same width")
    func marksAreUniform() {
        let span = FeetInch(feet: 8, inches: 3, num: 5, den: 8)
        let parts = 7
        let marks = EqualSpacing.marks(span: span, parts: parts)
        let bay = EqualSpacing.bay(span: span, parts: parts)
        for i in 1..<marks.count {
            #expect(marks[i - 1] < marks[i], "marks must strictly increase")
            #expect(marks[i] - marks[i - 1] == bay, "bay \(i) differs from the computed bay width")
        }
    }

    /// The exact case the differentiator was written for: 7 balusters in 62 1/4".
    @Test("7 balusters evenly spaced in 62 1/4\"")
    func balusterLayout() {
        let span = FeetInch(inches: 62, num: 1, den: 4)
        let width = FeetInch(inches: 1, num: 1, den: 2)          // 1 1/2" balusters
        let centres = EqualSpacing.itemCentres(span: span, count: 7, itemWidth: width)
        let gap = EqualSpacing.itemGap(span: span, count: 7, itemWidth: width)
        guard let centres, let gap else { Issue.record("layout should fit"); return }

        #expect(centres.count == 7)
        // 62.25 - 7(1.5) = 51.75 free, over 8 gaps = 6.46875" each — an exact rational.
        #expect(gap.inches == Rational(207, 32), "gap must be exactly 207/32\", got \(gap.inches)")
        // Gaps are equal at both ends: first centre is gap + half a baluster from the end,
        // and the last centre is the same distance from the other end.
        let fromStart = centres.first! - FeetInch.zero
        let fromEnd = span - centres.last!
        #expect(fromStart == fromEnd, "the layout must be symmetric: \(fromStart) vs \(fromEnd)")
        // And the centres are evenly pitched.
        for i in 1..<centres.count {
            #expect(centres[i] - centres[i - 1] == gap + width, "uneven baluster pitch at \(i)")
        }
    }

    @Test("items that cannot fit return nil, not a negative gap")
    func overfullLayoutIsNil() {
        let span = FeetInch(inches: 10)
        #expect(EqualSpacing.itemCentres(span: span, count: 8, itemWidth: FeetInch(inches: 2)) == nil)
        #expect(EqualSpacing.itemGap(span: span, count: 8, itemWidth: FeetInch(inches: 2)) == nil)
    }

    /// 5★ 2024-03-14: *"The only thing I wish it had was an automatic halving setting."*
    @Test("halving and quartering, the most-requested missing feature")
    func halvesAndQuarters() {
        let drawer = FeetInch(inches: 17, num: 7, den: 16)       // the review's own example
        #expect(EqualSpacing.half(drawer).inches == Rational(279, 32))
        #expect(EqualSpacing.half(drawer).formatted(toDenominator: 32) == "8-23/32\"")

        let q = EqualSpacing.quarters(drawer)
        #expect(q.count == 3, "three interior marks divide a face into four")
        #expect(q[1] == EqualSpacing.half(drawer), "the middle quarter mark is the midpoint")
        #expect(q[0] + q[2] == drawer, "quarter marks are symmetric about the centre")
    }

    @Test("interior marks drop both ends")
    func interiorMarks() {
        let span = FeetInch(feet: 10)
        #expect(EqualSpacing.interiorMarks(span: span, parts: 4).count == 3)
        #expect(EqualSpacing.interiorMarks(span: span, parts: 1).isEmpty)
    }

    // MARK: - OnCenter: PUBLISHED values, IDENTITY arithmetic

    @Test("the published spacings are exact, and 19.2\" is marked as derived")
    func spacingProvenance() {
        #expect(OnCenter.Spacing.sixteen.inches == Rational(16))
        #expect(OnCenter.Spacing.twentyFour.inches == Rational(24))
        #expect(OnCenter.Spacing.nineteenTwo.inches == Rational(96, 5), "19.2\" is exactly 96/5")

        #expect(OnCenter.Spacing.sixteen.isPublished)
        #expect(OnCenter.Spacing.twentyFour.isPublished)
        #expect(!OnCenter.Spacing.nineteenTwo.isPublished,
                "19.2 o.c. is NOT in USDA AH-73 and must not claim to be")

        #expect(OnCenter.Spacing.sixteen.provenance.contains("Agriculture Handbook 73"))
        #expect(OnCenter.Spacing.nineteenTwo.provenance.contains("Not published"))
    }

    @Test("five bays of 19.2\" make exactly one 8-foot sheet")
    func nineteenTwoIsTheSheetModule() {
        let five = OnCenter.Spacing.nineteenTwo.inches * Rational(5)
        #expect(five == Rational(96), "19.2 x 5 must be exactly 96\" — that is where it comes from")
    }

    @Test("a 20-foot wall at 16\" o.c.: 16 studs and a 4-inch last bay")
    func wallLayoutWithOddBay() {
        let span = FeetInch(feet: 20)                             // 240"
        let l = OnCenter.layout(span: span, spacing: .sixteen)
        #expect(l.memberCount == 16, "marks at 0,16,...,240 is 16 studs, got \(l.memberCount)")
        #expect(l.marks.last == FeetInch(inches: 240))
        #expect(l.isEven, "240 divides by 16 exactly")
        #expect(l.lastBay == .zero)
    }

    @Test("an odd last bay is reported, never hidden")
    func oddLastBayIsReported() {
        let span = FeetInch(feet: 20, inches: 7, num: 1, den: 2)  // 247 1/2"
        let l = OnCenter.layout(span: span, spacing: .sixteen)
        #expect(!l.isEven)
        #expect(l.marks.last == FeetInch(inches: 240), "the last full mark is at 240\"")
        #expect(l.lastBay == FeetInch(inches: 7, num: 1, den: 2), "the odd bay is 7 1/2\", got \(l.lastBay)")
        #expect(l.lastBay < OnCenter.Spacing.sixteen.dimension, "an odd bay is shorter than a full one")
    }

    @Test("every mark plus the last bay reconstructs the span exactly")
    func layoutReconstructsSpan() {
        for sixteenths in stride(from: 16, through: 40 * 12 * 16, by: 397) {
            let span = FeetInch(inches: Rational(Int64(sixteenths), 16))
            for spacing in OnCenter.Spacing.allCases {
                let l = OnCenter.layout(span: span, spacing: spacing)
                #expect(l.marks.last! + l.lastBay == span,
                        "\(spacing) on \(span): marks end at \(l.marks.last!) + \(l.lastBay)")
                #expect(!l.lastBay.isNegative, "the last bay must never be negative")
                #expect(l.lastBay < spacing.dimension, "the last bay must be shorter than the spacing")
            }
        }
    }

    @Test("marks are monotonic and start at zero")
    func layoutMarksAreMonotonic() {
        let l = OnCenter.layout(span: FeetInch(feet: 32), spacing: .nineteenTwo)
        #expect(l.marks.first == .zero)
        for i in 1..<l.marks.count {
            #expect(l.marks[i - 1] < l.marks[i])
        }
    }

    @Test("a span shorter than one spacing gets a single mark at zero")
    func shortSpan() {
        let l = OnCenter.layout(span: FeetInch(inches: 10), spacing: .sixteen)
        #expect(l.memberCount == 1)
        #expect(l.lastBay == FeetInch(inches: 10))
    }
}
