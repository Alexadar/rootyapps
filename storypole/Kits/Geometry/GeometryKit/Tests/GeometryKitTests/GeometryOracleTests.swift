import Testing
import Foundation
@testable import GeometryKit

// Oracle = Pythagoras and closed-form trigonometry (identity) + published crown-molding tables.  identity/oracle-backed.
/// ORACLES:
///  • IDENTITY  — the Pythagorean theorem, cross-checked against the 3-4-5 and 5-12-13 integer
///    triples, which are exact and therefore a genuine check rather than a restatement.
///  • PUBLISHED — crown-molding tables, reproduced identically across trim references:
///    spring 38 degrees -> miter 31.62, bevel 33.86; spring 45 degrees -> 35.26, 30.00.
///    Tables are printed to 0.01 degrees, so that is the tolerance.
///  • IDENTITY  — those table values ARE atan(sin s * tan h) and asin(cos s * cos h), asserted
///    against the closed form so the transcription and the maths corroborate each other.
///  • INVARIANT — a square frame miters at 45 degrees; an octagon at 22.5; arch radius and rise
///    are inverses.
@Suite("Geometry — diagonal, miter, circle")
struct GeometryOracleTests {

    // MARK: - IDENTITY: squaring up

    @Test("the 3-4-5 and 5-12-13 triples are exact")
    func integerTriples() {
        #expect(Diagonal.hypotenuse(3, 4) == 5)
        #expect(Diagonal.hypotenuse(5, 12) == 13)
        #expect(Diagonal.hypotenuse(8, 15) == 17)
        #expect(abs(Diagonal.leg(diagonal: 5, otherLeg: 3) - 4) < 1e-12)
    }

    @Test("the 3-4-5 check scales")
    func threeFourFiveScales() {
        for k in [1.0, 2.0, 3.0, 12.5] {
            let t = Diagonal.threeFourFive(scale: k)
            #expect(abs(Diagonal.hypotenuse(t.a, t.b) - t.c) < 1e-9)
        }
    }

    @Test("hypotenuse and leg are inverses")
    func hypotenuseAndLegRoundTrip() {
        for a in stride(from: 1.0, through: 40.0, by: 3.0) {
            for b in stride(from: 1.0, through: 40.0, by: 3.0) {
                let d = Diagonal.hypotenuse(a, b)
                #expect(abs(Diagonal.leg(diagonal: d, otherLeg: a) - b) < 1e-9)
            }
        }
    }

    @Test("an impossible leg returns zero, not NaN")
    func impossibleLeg() {
        let l = Diagonal.leg(diagonal: 3, otherLeg: 5)
        #expect(l == 0)
        #expect(!l.isNaN)
    }

    /// The practical case: a room measured 12' x 16' should have a 20' diagonal.
    @Test("squaring up a room")
    func squaringUp() {
        #expect(Diagonal.isSquare(length: 144, width: 192, measuredDiagonal: 240, tolerance: 0.125))
        #expect(!Diagonal.isSquare(length: 144, width: 192, measuredDiagonal: 241, tolerance: 0.125))
        #expect(abs(Diagonal.outOfSquare(length: 144, width: 192, measuredDiagonal: 241) - 1) < 1e-9)
        #expect(Diagonal.outOfSquare(length: 144, width: 192, measuredDiagonal: 239) < 0,
                "a short diagonal reports negative")
    }

    // MARK: - PUBLISHED: crown tables

    @Test("compound crown settings match the published tables")
    func publishedCrownTables() {
        let s38 = Miter.compound(springDeg: 38, sides: 4)
        #expect(abs(s38.miter - 31.62) < 0.01)
        #expect(abs(s38.bevel - 33.86) < 0.01)
        let s45 = Miter.compound(springDeg: 45, sides: 4)
        #expect(abs(s45.miter - 35.26) < 0.01)
        #expect(abs(s45.bevel - 30.00) < 0.01)
    }

    /// The published constants re-derived from the closed form — independent of the transcription.
    @Test("the crown table values ARE the closed-form trig")
    func crownTableIsTheClosedForm() {
        let d2r = Double.pi / 180, r2d = 180 / Double.pi
        for spring in [38.0, 45.0, 52.0] {
            for sides in [4, 6, 8] {
                let got = Miter.compound(springDeg: spring, sides: sides)
                let half = (180.0 / Double(sides)) * d2r
                let s = spring * d2r
                #expect(abs(got.miter - atan(sin(s) * tan(half)) * r2d) < 1e-9)
                #expect(abs(got.bevel - asin(cos(s) * cos(half)) * r2d) < 1e-9)
            }
        }
    }

    @Test("simple frame miters")
    func simpleMiters() {
        #expect(abs(Miter.simpleDeg(sides: 4) - 45) < 1e-12, "a square frame")
        #expect(abs(Miter.simpleDeg(sides: 8) - 22.5) < 1e-12, "an octagon")
        #expect(abs(Miter.simpleDeg(sides: 6) - 30) < 1e-12, "a hexagon")
        #expect(abs(Miter.simpleDeg(sides: 3) - 60) < 1e-12, "a triangle")
    }

    @Test("a measured corner mitres at half its supplement")
    func cornerMiter() {
        #expect(abs(Miter.forCornerDeg(90) - 45) < 1e-12, "a square corner")
        #expect(abs(Miter.forCornerDeg(135) - 22.5) < 1e-12, "a 135-degree corner")
        // An out-of-square corner is the whole reason this exists: 92 degrees gives 44.
        #expect(abs(Miter.forCornerDeg(92) - 44) < 1e-12)
        // Two mitres close the corner.
        for corner in stride(from: 30.0, through: 170.0, by: 10.0) {
            #expect(abs(2 * Miter.forCornerDeg(corner) + corner - 180) < 1e-12)
        }
    }

    // MARK: - IDENTITY: circles

    @Test("circumference and area")
    func circles() {
        #expect(abs(Circle.circumference(radius: 1) - 2 * .pi) < 1e-12)
        #expect(abs(Circle.circumference(diameter: 2) - 2 * .pi) < 1e-12)
        #expect(abs(Circle.area(radius: 1) - .pi) < 1e-12)
        #expect(abs(Circle.area(diameter: 2) - .pi) < 1e-12)
    }

    @Test("pipe wrap is the outside circumference")
    func pipeWrap() {
        #expect(abs(Circle.pipeWrap(outsideDiameter: 4) - Circle.circumference(diameter: 4)) < 1e-15)
        #expect(abs(Circle.pipeWrap(outsideDiameter: 4) - 12.566370614) < 1e-8)
    }

    @Test("arc length and the full circle agree")
    func arcLength() {
        #expect(abs(Circle.arcLength(radius: 1, angleDeg: 360) - 2 * .pi) < 1e-12)
        #expect(abs(Circle.arcLength(radius: 2, angleDeg: 90) - .pi) < 1e-12)
    }

    @Test("a semicircular segment is half the circle")
    func semicircleSegment() {
        #expect(abs(Circle.segmentArea(radius: 1, angleRadians: .pi) - .pi / 2) < 1e-12)
    }

    @Test("arch rise and radius are inverses")
    func archRoundTrip() {
        for span in [24.0, 36.0, 60.0] {
            for rise in [3.0, 6.0, 11.0] {
                guard let r = Circle.radiusFrom(span: span, rise: rise) else {
                    Issue.record("radius should exist for span \(span) rise \(rise)"); continue
                }
                guard let back = Circle.archRise(span: span, radius: r) else {
                    Issue.record("rise should exist for span \(span) radius \(r)"); continue
                }
                #expect(abs(back - rise) < 1e-9, "span \(span) rise \(rise) round-tripped to \(back)")
            }
        }
    }

    @Test("a semicircular arch has a rise of half its span")
    func semicircularArch() {
        #expect(abs(Circle.archRise(span: 20, radius: 10)! - 10) < 1e-12)
        #expect(Circle.archRise(span: 20, radius: 9) == nil, "a radius too small cannot span the opening")
        #expect(Circle.radiusFrom(span: 20, rise: 0) == nil, "a flat arch has no circle")
    }
}
