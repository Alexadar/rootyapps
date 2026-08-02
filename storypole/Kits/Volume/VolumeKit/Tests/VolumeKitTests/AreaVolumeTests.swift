import Testing
import Foundation
@testable import VolumeKit

// Oracle = closed-form geometry (identity) + NIST SP 811 §B.8 for the cubic-yard factor.  identity/oracle-backed.
/// ORACLES:
///  • IDENTITY  — closed-form geometry: circle = pi r^2, Heron, cylinder = pi r^2 h, sphere = 4/3 pi r^3.
///    Heron on a 3-4-5 triangle must equal 1/2 b h = 6, which is a genuine cross-check because the
///    two formulas share no terms.
///  • PUBLISHED — NIST SP 811 §B.8: cubic yard -> cubic metre = 7.645549E-01.
///    https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication811e2008.pdf (retrieved 2026-07-29)
///  • IDENTITY  — 27 ft^3 per yd^3 and 1728 in^3 per ft^3 are 3^3 and 12^3.
///  • MODEL     — QUIKRETE bag yields are a manufacturer datasheet, not a standard, and waste
///    percentage is an estimating convention. Neither is asserted as an oracle.
@Suite("Area and Volume")
struct AreaVolumeTests {

    static let sp811 = """
        NIST SP 811 (2008) §B.8; \
        https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication811e2008.pdf \
        (US Government work, public domain); retrieved 2026-07-29.
        """

    @Test("the citation is complete")
    func citation() {
        #expect(Self.sp811.contains("http"))
        #expect(Self.sp811.contains("SP 811"))
    }

    // MARK: - IDENTITY: areas

    @Test("plane areas")
    func areas() {
        #expect(Area.rectangle(length: 3, width: 4) == 12)
        #expect(Area.triangle(base: 3, height: 4) == 6)
        #expect(Area.trapezoid(base1: 3, base2: 5, height: 4) == 16)
    }

    /// Heron cross-checked against 1/2 b h on the 3-4-5 right triangle — two independent formulas
    /// that must agree.
    @Test("Heron agrees with half base times height on a 3-4-5 triangle")
    func heronCrossCheck() {
        #expect(abs(Area.triangle(a: 3, b: 4, c: 5) - 6) < 1e-9)
        #expect(abs(Area.triangle(a: 3, b: 4, c: 5) - Area.triangle(base: 3, height: 4)) < 1e-9)
        #expect(abs(Area.triangle(a: 5, b: 12, c: 13) - 30) < 1e-9, "the 5-12-13 triple too")
    }

    @Test("an impossible triangle returns zero, not NaN")
    func impossibleTriangle() {
        let a = Area.triangle(a: 1, b: 1, c: 5)
        #expect(a == 0)
        #expect(!a.isNaN)
    }

    /// Defect ③ in its simplest form: square footage from two dimensions in inches.
    @Test("square footage from inches")
    func squareFeet() {
        #expect(abs(Area.squareFeet(lengthIn: 144, widthIn: 144) - 144) < 1e-9, "12ft x 12ft = 144 sq ft")
        #expect(abs(Area.squareFeet(lengthIn: 148, widthIn: 148) - 21904.0 / 144.0) < 1e-9)
    }

    // MARK: - IDENTITY: volumes

    @Test("solids")
    func volumes() {
        #expect(Volume.box(length: 2, width: 3, height: 4) == 24)
        #expect(abs(Volume.cylinder(radius: 1, height: 1) - .pi) < 1e-12)
        #expect(abs(Volume.cylinder(diameter: 2, height: 1) - .pi) < 1e-12)
        #expect(abs(Volume.cone(radius: 1, height: 3) - .pi) < 1e-12)
        #expect(abs(Volume.sphere(radius: 1) - 4.0 / 3.0 * .pi) < 1e-12)
    }

    @Test("a cone is one third of its cylinder")
    func coneIsThirdOfCylinder() {
        for r in [0.5, 1.0, 3.25] {
            for h in [1.0, 2.5, 9.0] {
                #expect(abs(Volume.cone(radius: r, height: h) * 3 - Volume.cylinder(radius: r, height: h)) < 1e-9)
            }
        }
    }

    // MARK: - PUBLISHED: the cubic-yard factor

    @Test("SP 811 §B.8 — cubic yard to cubic metre is 7.645549E-01")
    func cubicYardToMetre() {
        #expect(abs(Volume.cubicMetresPerCubicYard - 0.7645549) < 5e-8,
                "got \(Volume.cubicMetresPerCubicYard)")
        #expect(abs(Volume.cubicYardsToMetres(1) - 0.7645549) < 5e-8)
        // And it must BE 0.9144 cubed, since the yard is exactly 0.9144 m.
        #expect(abs(Volume.cubicMetresPerCubicYard - pow(0.9144, 3)) < 1e-15)
    }

    @Test("27 cubic feet per cubic yard and 1728 cubic inches per cubic foot")
    func constructionConversions() {
        #expect(Volume.cubicFeetPerCubicYard == 27, "3 cubed")
        #expect(Volume.cubicInchesPerCubicFoot == 1728, "12 cubed")
        #expect(Volume.cubicFeetToYards(27) == 1)
        #expect(Volume.cubicYardsToFeet(1) == 27)
        #expect(Volume.cubicInchesToFeet(1728) == 1)
    }

    @Test("cubic-feet and cubic-yard conversions round-trip")
    func conversionsRoundTrip() {
        for ft3 in [1.0, 27.0, 33.333, 100.5] {
            #expect(abs(Volume.cubicYardsToFeet(Volume.cubicFeetToYards(ft3)) - ft3) < 1e-9)
        }
    }

    // MARK: - Concrete (model, not oracle)

    @Test("slab volume and cubic yards")
    func slab() {
        let ft3 = Concrete.slabCubicFeet(lengthFt: 10, widthFt: 10, thicknessInches: 4)
        #expect(abs(ft3 - 100.0 / 3.0) < 1e-9, "10x10 at 4\" is 33 1/3 ft3")
        #expect(abs(Concrete.cubicYards(cubicFeet: ft3) - (100.0 / 3.0) / 27.0) < 1e-9)
    }

    @Test("a 12-inch sonotube 48 inches deep is exactly pi cubic feet")
    func column() {
        #expect(abs(Concrete.columnCubicFeet(diameterInches: 12, heightInches: 48) - .pi) < 1e-9)
    }

    @Test("bag counts round up — you cannot buy part of a bag")
    func bagsRoundUp() {
        #expect(Concrete.bags(cubicFeet: 27, yieldFt3: Concrete.bag80lbYieldFt3) == 45)
        #expect(Concrete.bags(cubicFeet: 27, yieldFt3: Concrete.bag60lbYieldFt3) == 60)
        #expect(Concrete.bags(cubicFeet: 27, yieldFt3: Concrete.bag40lbYieldFt3) == 90)
        #expect(Concrete.bags(cubicFeet: 0.61, yieldFt3: 0.60) == 2, "just over one bag needs two")
        #expect(Concrete.bags(cubicFeet: 1, yieldFt3: 0) == 0, "a zero yield must not divide by zero")
    }

    @Test("waste allowance is a plain percentage — a convention, not an oracle")
    func waste() {
        #expect(abs(Concrete.withWaste(cubicFeet: 27, wastePct: 10) - 29.7) < 1e-9)
        #expect(Concrete.withWaste(cubicFeet: 27, wastePct: 0) == 27)
    }
}
