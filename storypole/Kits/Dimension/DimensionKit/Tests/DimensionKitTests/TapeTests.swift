import Testing
import Foundation
@testable import DimensionKit

// Oracle = the physical behaviour of a real tape measure (convention) + defect ④ from the reviews.  invariant.
/// ORACLES:
///  • INVARIANT — nothing is ever drawn past the longest real tape. This is defect ④:
///    *"No tape goes into the 200s that I've ever seen."* (3★ 2025-10-14). `smallest(for:)`
///    returning `nil` is the mechanism, and there is deliberately no fallback to the longest tape.
///  • INVARIANT — `position(of:)` is the entire tape graphic reduced to one function, so defect ②
///    (*"It's an 1\" short on every measurement"*, 1★ 2020-11-13) is testable before any pixel.
///  • CONVENTION — the blade lengths are common US retail sizes, labelled as convention, not as a
///    published standard. Nothing computes from them except the drawing extent.
@Suite("Tape — realism and mark placement")
struct TapeTests {

    @Test("the catalogue is ordered and plausible")
    func catalogueIsOrdered() {
        let lengths = Tape.catalogue.map(\.lengthFeet)
        #expect(lengths == lengths.sorted(), "catalogue must be shortest-first")
        #expect(Set(lengths).count == lengths.count, "duplicate blade length")
        #expect(Tape.longest.lengthFeet == 35)
    }

    @Test("the smallest tape that fits is chosen")
    func choosesSmallestFit() {
        #expect(Tape.smallest(for: FeetInch(feet: 3))?.lengthFeet == 12)
        #expect(Tape.smallest(for: FeetInch(feet: 12))?.lengthFeet == 12, "exactly 12 ft fits a 12 ft tape")
        #expect(Tape.smallest(for: FeetInch(feet: 12, inches: 1))?.lengthFeet == 16)
        #expect(Tape.smallest(for: FeetInch(feet: 20))?.lengthFeet == 25)
        #expect(Tape.smallest(for: FeetInch(feet: 35))?.lengthFeet == 35)
    }

    /// Defect ④. This is the assertion that makes an over-long tape unshippable.
    @Test("nothing longer than a real tape can be drawn")
    func nothingBeyondARealTape() {
        #expect(Tape.smallest(for: FeetInch(feet: 36)) == nil)
        #expect(Tape.smallest(for: FeetInch(feet: 100)) == nil)
        #expect(Tape.smallest(for: FeetInch(inches: 500)) == nil, "500 in is 41'8\", beyond every real tape")
        // The carpenter's actual complaint was about LABELLING, not extent: 250 inches is 20'10",
        // which genuinely fits a 25 ft tape — what must never happen is drawing it marked "250".
        // That half of defect ④ is asserted in `inchMarks`, below.
        #expect(Tape.smallest(for: FeetInch(inches: 250))?.lengthFeet == 25)
    }

    @Test("a negative dimension is never on a tape")
    func negativesNeverFit() {
        #expect(Tape.smallest(for: FeetInch(inches: -1)) == nil)
        for t in Tape.catalogue {
            #expect(!t.contains(FeetInch(feet: -1)), "a tape has no negative side")
        }
    }

    /// Defect ②, as arithmetic.
    @Test("mark position is exact at the ends and the middle")
    func positionIsExact() {
        let t = Tape(lengthFeet: 25)
        #expect(t.position(of: .zero) == 0)
        #expect(t.position(of: FeetInch(feet: 25)) == 1)
        #expect(t.position(of: FeetInch(feet: 12, inches: 6)) == 0.5)
    }

    @Test("position is monotonic — a bigger measurement is never further left")
    func positionIsMonotonic() {
        let t = Tape(lengthFeet: 25)
        var previous = -1.0
        for n in stride(from: 0, through: 25 * 12 * 16, by: 13) {
            let v = FeetInch(inches: Rational(Int64(n), 16))
            guard let p = t.position(of: v) else { continue }
            #expect(p > previous || n == 0, "position went backwards at \(v)")
            #expect(p >= 0 && p <= 1, "position \(p) out of range at \(v)")
            previous = p
        }
    }

    @Test("position is nil for anything off the blade")
    func positionNilOffBlade() {
        let t = Tape(lengthFeet: 16)
        #expect(t.position(of: FeetInch(feet: 17)) == nil)
        #expect(t.position(of: FeetInch(inches: -1)) == nil)
    }

    @Test("inch marks span the blade and are labelled in feet and inches")
    func inchMarks() {
        let t = Tape(lengthFeet: 12)
        let marks = t.inchMarks()
        #expect(marks.count == 12 * 12 + 1, "0 through 144 inclusive")
        #expect(marks.first == .zero)
        #expect(marks.last == FeetInch(feet: 12))
        // Defect ④'s other half: the label is feet+inches, never a running inch count.
        #expect(marks[100].formatted() == "8' 4\"", "the 100-inch mark reads 8' 4\", not 100\"")
        #expect(marks[144].formatted() == "12'")
    }
}

// Oracle = the inverse of the tested position map.  invariant.
/// ORACLES:
///  • INVARIANT — `value(atPosition: position(of: v)) == v` for EVERY sixteenth on EVERY blade.
///    This is the guard that makes the blade safe as an input. `position(of:)` divides through
///    `Double`; without the snap the round trip drifts, and drift here is defect ② —
///    *"always shows your measurement 1/16 of an inch off and it's infuriating"* (1★ 2020-12-25).
///  • INVARIANT — scrubbing is monotonic, clamps at both ends, and always lands on the denominator.
@Suite("Tape — scrubbing the blade as an input")
struct TapeScrubTests {

    @Test("position round-trips exactly for every sixteenth on every blade")
    func roundTripExact() {
        for tape in Tape.catalogue {
            let sixteenths = tape.lengthFeet * 12 * 16
            for n in stride(from: 0, through: sixteenths, by: 7) {
                let v = FeetInch(inches: Rational(Int64(n), 16))
                guard let p = tape.position(of: v) else {
                    Issue.record("\(v) should be on a \(tape.lengthFeet) ft blade"); continue
                }
                let back = tape.value(atPosition: p, denominator: 16)
                #expect(back == v, "\(tape): \(v) -> p=\(p) -> \(back)")
            }
        }
    }

    @Test("round-trip holds at the finest denominator the app offers")
    func roundTripAtSixtyFourths() {
        let tape = Tape(lengthFeet: 12)
        for n in stride(from: 0, through: 12 * 12 * 64, by: 29) {
            let v = FeetInch(inches: Rational(Int64(n), 64))
            let p = tape.position(of: v)!
            #expect(tape.value(atPosition: p, denominator: 64) == v, "64ths failed at \(v)")
        }
    }

    @Test("position is clamped, never extrapolated")
    func positionClamped() {
        let t = Tape(lengthFeet: 25)
        #expect(t.value(atPosition: -5) == .zero, "before the hook is zero")
        #expect(t.value(atPosition: 2) == FeetInch(feet: 25), "past the end is the end")
        #expect(t.value(atPosition: .nan) == .zero, "a non-finite position must not propagate")
    }

    @Test("every scrubbed value lands on the chosen denominator")
    func scrubSnapsToDenominator() {
        let t = Tape(lengthFeet: 25)
        let window = FeetInch(inches: 12)
        for den: Int64 in [2, 4, 8, 16, 32, 64] {
            var v = FeetInch(feet: 3)
            for i in 1...60 {
                v = t.scrubbing(from: v, byFraction: Double(i) * 0.0013 - 0.03,
                                windowSpan: window, denominator: den)
                let scaled = v.inches * Rational(den)
                #expect(scaled.den == 1, "1/\(den): \(v) is not on the denominator (\(v.inches))")
            }
        }
    }

    @Test("dragging left increases the value, right decreases it — like pulling a tape out")
    func scrubDirection() {
        let t = Tape(lengthFeet: 25)
        let w = FeetInch(inches: 12)
        let start = FeetInch(feet: 4)
        let left  = t.scrubbing(from: start, byFraction: -0.5, windowSpan: w)
        let right = t.scrubbing(from: start, byFraction:  0.5, windowSpan: w)
        #expect(start < left,  "dragging left must increase")
        #expect(right < start, "dragging right must decrease")
        // Half a 12" window is 6".
        #expect(left  == FeetInch(feet: 4, inches: 6))
        #expect(right == FeetInch(feet: 3, inches: 6))
    }

    @Test("a scrub can never leave the blade")
    func scrubClamps() {
        let t = Tape(lengthFeet: 12)
        let w = FeetInch(inches: 24)
        var v = FeetInch(inches: 2)
        for _ in 0..<50 { v = t.scrubbing(from: v, byFraction: 1, windowSpan: w) }
        #expect(v == .zero, "scrubbing right forever stops at the hook, never negative")
        v = FeetInch(feet: 11)
        for _ in 0..<50 { v = t.scrubbing(from: v, byFraction: -1, windowSpan: w) }
        #expect(!(t.length < v), "scrubbing left forever stops at the end of the blade")
        #expect(t.contains(v))
    }

    @Test("a one-sixteenth drag on a 12-inch window moves exactly one sixteenth")
    func fineDetentIsReachable() {
        let t = Tape(lengthFeet: 25)
        let window = FeetInch(inches: 12)
        let start = FeetInch(feet: 5)
        // 1/16" of a 12" window is 1/192 of the width — the smallest move that must register.
        let moved = t.scrubbing(from: start, byFraction: -1.0 / 192.0, windowSpan: window)
        #expect(moved == start + FeetInch(inches: 0, num: 1, den: 16),
                "expected one sixteenth, got \(moved.formatted(toDenominator: 16))")
    }

    @Test("scrubbing by nothing changes nothing")
    func zeroScrubIsIdentity() {
        let t = Tape(lengthFeet: 16)
        let v = FeetInch(feet: 7, inches: 3, num: 5, den: 16)
        #expect(t.scrubbing(from: v, byFraction: 0, windowSpan: FeetInch(inches: 12)) == v)
    }
}

// Oracle = the variable-scrubbing idiom (iOS media players, YouTube).  invariant.
/// ORACLES:
///  • INVARIANT — scales are strictly ordered: coarser tiers cover more blade per drag, so a
///    "finer" scale can never travel further than a coarser one.
///  • INVARIANT — vertical drift maps monotonically onto the tiers, and every tier is reachable.
///    On the blade is PRECISE and away is COARSE — the inverse of a media scrubber, because on a
///    tape the precision lives on the blade where the graduations are.
///  • INVARIANT — the finest tier can still resolve a sixteenth across a realistic view width,
///    and the coarsest can cross a whole 25 ft tape in one drag. Those two together are the whole
///    reason the scale is variable rather than fixed.
@Suite("Tape — variable scrub scale")
struct ScrubScaleTests {

    @Test("coarser scales cover more blade")
    func scalesAreOrdered() {
        let all = Tape.ScrubScale.allCases
        for (a, b) in zip(all, all.dropFirst()) {
            #expect(a < b, "\(a.name) must sort before \(b.name)")
            #expect(b.span < a.span, "\(b.name) must cover less blade than \(a.name)")
            #expect(!b.span.inches.isZero, "\(b.name) must cover some blade")
        }
    }

    @Test("drift coarsens monotonically, and every tier is reachable")
    func driftMapsMonotonically() {
        var seen: Set<Tape.ScrubScale> = []
        var previous = Tape.ScrubScale.precise
        for d in stride(from: 0.0, through: 400, by: 2) {
            let s = Tape.ScrubScale.forVerticalDrift(d)
            #expect(s <= previous, "scale got FINER as the finger moved away, at \(d) pt")
            previous = s
            seen.insert(s)
        }
        #expect(seen.count == Tape.ScrubScale.allCases.count, "some tier is unreachable: \(seen)")
        #expect(Tape.ScrubScale.forVerticalDrift(0) == .precise, "a finger on the blade is precise")
        #expect(Tape.ScrubScale.forVerticalDrift(-300) == .coarse, "drift is symmetric")
        #expect(Tape.ScrubScale.forVerticalDrift(300) == .coarse)
    }

    @Test("a small wobble does not change scale")
    func smallWobbleIsStable() {
        for d in stride(from: 0.0, through: 40, by: 1) {
            #expect(Tape.ScrubScale.forVerticalDrift(d) == .precise,
                    "a \(d) pt wobble must not leave the precise tier")
        }
    }

    /// The two ends of the trade-off, stated as numbers rather than opinion.
    @Test("the finest scale resolves a sixteenth; the coarsest crosses a 25 ft tape")
    func theTradeOffHolds() {
        let viewWidth = 360.0                       // a phone, in points

        let finest = Tape.ScrubScale.precise.span.inchesValue
        let ptPerSixteenth = viewWidth / (finest * 16)
        #expect(ptPerSixteenth >= 8, "a sixteenth must be a comfortable target, got \(ptPerSixteenth) pt")

        let coarsest = Tape.ScrubScale.coarse.span.inchesValue
        #expect(coarsest >= 96, "one drag should cover at least 8 ft, got \(coarsest) in")
        let dragsFor25ft = (25.0 * 12) / coarsest
        #expect(dragsFor25ft <= 4, "crossing a 25 ft tape should take a few drags, not \(dragsFor25ft)")
    }

    @Test("scrubbing honours the chosen scale")
    func scrubUsesTheScale() {
        let t = Tape(lengthFeet: 35)
        let start = FeetInch(feet: 10)
        // Half a full-width drag moves half the scale's span, whatever the scale.
        for scale in Tape.ScrubScale.allCases {
            let moved = t.scrubbing(from: start, byFraction: -0.5, windowSpan: scale.span)
            let delta = moved - start
            let expected = scale.span / Rational(2)
            #expect(delta == expected,
                    "\(scale.name): moved \(delta.formatted()) expected \(expected.formatted())")
        }
    }
}
