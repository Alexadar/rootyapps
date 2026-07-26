import Testing
import Foundation
@testable import GeometryKit

/// Calc #6 — area & volume.
///
/// ORACLES (identity/definition, cross-checked numerically): closed-form geometry —
/// circle = πr², circumference = 2πr, Heron, cylinder = πr²h, sphere = 4/3·πr³, 27 ft³/yd³.
/// A right-3-4-5 triangle's area (6) is both the Heron result and ½·base·height — a published
/// cross-check on Heron.
@Suite struct GeometryOracle {

    @Test func areas() {
        #expect(abs(Area.rectangle(length: 3, width: 4) - 12) < 1e-12)
        #expect(abs(Area.triangle(base: 3, height: 4) - 6) < 1e-12)
        #expect(abs(Area.triangle(a: 3, b: 4, c: 5) - 6) < 1e-9)          // Heron == ½·3·4 (3-4-5)
        #expect(abs(Area.trapezoid(base1: 3, base2: 5, height: 4) - 16) < 1e-12)
    }

    @Test func circles() {
        #expect(abs(Area.circle(radius: 1) - Double.pi) < 1e-12)          // πr², r=1 → π
        #expect(abs(Area.circle(diameter: 2) - Double.pi) < 1e-12)
        #expect(abs(Area.circumference(radius: 1) - 2 * Double.pi) < 1e-12)
        #expect(abs(Area.circle(radius: 2) - 4 * Double.pi) < 1e-12)
    }

    @Test func circularSegmentSemicircle() {
        // θ = π (semicircle) → ½r²(π − 0) = ½πr²; r=1 → π/2.
        #expect(abs(Area.circularSegment(radius: 1, angleRadians: .pi) - Double.pi / 2) < 1e-12)
    }

    @Test func volumes() {
        #expect(abs(Volume.box(length: 2, width: 3, height: 4) - 24) < 1e-12)
        #expect(abs(Volume.cylinder(radius: 1, height: 1) - Double.pi) < 1e-12)   // πr²h, r=h=1 → π
        #expect(abs(Volume.cone(radius: 1, height: 3) - Double.pi) < 1e-12)       // ⅓πr²h
        #expect(abs(Volume.sphere(radius: 1) - 4.0 / 3.0 * Double.pi) < 1e-12)
    }

    @Test func guardsNoCrash() {
        #expect(Area.triangle(a: 1, b: 1, c: 5) == 0)              // impossible triangle → 0, not NaN
        #expect(Area.circle(radius: 0) == 0)
        #expect(Volume.cylinder(radius: 0, height: 0) == 0)
    }

    @Test func constructionConversions() {
        #expect(abs(Volume.cubicFeetToYards(27) - 1) < 1e-12)            // 27 ft³ = 1 yd³
        #expect(abs(Volume.cubicYardsToFeet(1) - 27) < 1e-12)
        #expect(abs(Volume.cubicInchesToFeet(1728) - 1) < 1e-12)        // 12³ in³ = 1 ft³
    }
}
