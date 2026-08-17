import Testing
import Foundation
@testable import DuctKit

/// Exact unit factors, used only to state results in the units the published data is printed in.
enum IP {
    static let cubicMetresPerCFM = (0.3048 * 0.3048 * 0.3048) / 60
    static let metresPerInch = 0.0254
    static let metresPerFootPerMinute = 0.3048 / 60
    /// One inch w.g. per 100 ft, in Pa/m.
    static let pascalsPerMetrePerInchWGPer100Feet = 248.84 / (100 * 0.3048)
    /// The roughness the published friction chart is drawn for: 0.0003 ft.
    static let chartRoughness = 0.0003 * 0.3048
}

/// # The oracle
///
/// The independent reference is the **published friction-chart equation**,
/// `Δp = 0.109136 Q^1.9 / D^5.02` (Δp in in w.g./100 ft, Q in CFM, D in inches), a curve fit
/// ASHRAE publishes for galvanized duct at standard air. DuctKit implements the underlying
/// Colebrook–White physics instead, so the two are genuinely different routes to the same answer:
/// agreement is evidence, and the size of the residual disagreement is the curve fit's own error.
@Suite("Duct friction against the published chart equation")
struct DuctSizingOracleTests {

    /// The published curve fit, solved for diameter in inches.
    static func chartDiameterInches(cfm: Double, frictionInWGPer100Feet: Double) -> Double {
        pow(0.109136 * pow(cfm, 1.9) / frictionInWGPer100Feet, 1 / 5.02)
    }

    struct ChartPoint {
        let cfm: Double
        let friction: Double
    }

    /// Spanning the chart: a bathroom fan to a rooftop unit.
    static let chartPoints: [ChartPoint] = [
        .init(cfm: 100, friction: 0.08), .init(cfm: 400, friction: 0.08),
        .init(cfm: 850, friction: 0.08), .init(cfm: 1000, friction: 0.10),
        .init(cfm: 2000, friction: 0.08), .init(cfm: 4000, friction: 0.10),
        .init(cfm: 10000, friction: 0.10), .init(cfm: 850, friction: 0.30),
        .init(cfm: 20000, friction: 0.15),
    ]

    @Test("Colebrook sizing agrees with the chart equation", arguments: chartPoints)
    func agreesWithTheChartEquation(_ point: ChartPoint) throws {
        let diameter = try DuctSizing.diameter(
            flow: point.cfm * IP.cubicMetresPerCFM,
            frictionRate: point.friction * IP.pascalsPerMetrePerInchWGPer100Feet,
            absoluteRoughness: IP.chartRoughness)

        let inches = diameter / IP.metresPerInch
        let chart = Self.chartDiameterInches(cfm: point.cfm, frictionInWGPer100Feet: point.friction)
        let error = abs(inches - chart) / chart

        // 2.5 %: the measured spread is 0.5 % at the small end and 2.1 % at the large, which is
        // the curve fit drifting from the physics it was fitted to. Anything larger than this
        // would mean the Colebrook solve, not the fit, had moved.
        #expect(error < 0.025,
                "\(point.cfm) CFM at \(point.friction): Colebrook \(inches) in vs chart \(chart) in")
    }

    /// A hand-checkable point: 1,000 CFM in a 14-inch galvanized round duct.
    /// A = 1.0690 ft², V = 935 fpm, Re ≈ 111,000, f ≈ 0.0190, Δp ≈ 0.0886 in w.g./100 ft.
    @Test func workedPointInAFourteenInchDuct() throws {
        let flow = 1000 * IP.cubicMetresPerCFM
        let diameter = 14 * IP.metresPerInch

        let velocity = try DuctSizing.velocity(flow: flow, diameter: diameter)
        #expect(abs(velocity / IP.metresPerFootPerMinute - 935) < 1, "got \(velocity / IP.metresPerFootPerMinute) fpm")

        let re = try DuctSizing.reynoldsNumber(velocity: velocity, diameter: diameter,
                                               air: .standard)
        #expect(abs(re - 111_254) < 500, "got Re \(re)")

        let f = try DuctSizing.frictionFactor(reynoldsNumber: re,
                                              relativeRoughness: IP.chartRoughness / diameter)
        #expect(abs(f - 0.01895) < 1e-4, "got f \(f)")

        let friction = try DuctSizing.frictionRate(flow: flow, diameter: diameter,
                                                   absoluteRoughness: IP.chartRoughness)
        #expect(abs(friction / IP.pascalsPerMetrePerInchWGPer100Feet - 0.0886) < 0.001,
                "got \(friction / IP.pascalsPerMetrePerInchWGPer100Feet) in w.g./100 ft")
    }

    /// Friction and diameter must invert each other exactly, in both directions.
    @Test func sizingAndFrictionAreInverses() throws {
        for cfm in [150.0, 600, 1500, 5000] {
            for friction in [0.05, 0.08, 0.1, 0.2] {
                let target = friction * IP.pascalsPerMetrePerInchWGPer100Feet
                let flow = cfm * IP.cubicMetresPerCFM
                let d = try DuctSizing.diameter(flow: flow, frictionRate: target)
                let back = try DuctSizing.frictionRate(flow: flow, diameter: d)
                #expect(abs(back - target) / target < 1e-9,
                        "\(cfm) CFM at \(friction): friction came back as \(back) not \(target)")
            }
        }
    }

    @Test func velocityAndDiameterAreInverses() throws {
        for cfm in [150.0, 1500, 12000] {
            let flow = cfm * IP.cubicMetresPerCFM
            let d = try DuctSizing.diameter(flow: flow, velocity: 5.0)
            #expect(abs(try DuctSizing.velocity(flow: flow, diameter: d) - 5.0) < 1e-12)
        }
    }

    /// The friction factor itself — Colebrook against the Moody chart, both asymptotes, and the
    /// solved value substituted back into the implicit equation — is tested in `FluidKitTests`,
    /// which owns that code. What is asserted here is only that this Kit reaches it: a duct
    /// friction factor must be the fluid one, not a second implementation that drifted.
    @Test func theFrictionFactorIsTheSharedFluidOne() throws {
        #expect(abs(try DuctSizing.frictionFactor(reynoldsNumber: 1000, relativeRoughness: 0.001)
                        - 0.064) < 1e-12, "laminar")
        #expect(abs(try DuctSizing.frictionFactor(reynoldsNumber: 1e5, relativeRoughness: 0)
                        - 0.0180) < 5e-4, "smooth-pipe curve at Re 10⁵")
        #expect(DuctSizing.laminarLimit == 2300)
    }
}

@Suite("Roughness changes the answer")
struct RoughnessTests {

    /// **The dead-toggle regression.** The design scaffold declared four duct materials with
    /// published roughness values and then never passed them to the sizing routine, so changing
    /// the material changed nothing on screen. Every category must give a different diameter, and
    /// the spread must be large enough to see.
    @Test func everyRoughnessGivesADifferentAnswer() throws {
        let flow = 1000 * IP.cubicMetresPerCFM
        let target = 0.1 * IP.pascalsPerMetrePerInchWGPer100Feet

        let diameters = try DuctRoughness.allCases.map {
            try DuctSizing.diameter(flow: flow, frictionRate: target, roughness: $0)
                / IP.metresPerInch
        }

        for (a, b) in zip(diameters, diameters.dropFirst()) {
            #expect(b > a + 0.05, "rougher duct must need a bigger duct: \(diameters)")
        }
        // Measured: 13.52 · 13.66 · 13.77 · 14.57 · 15.48 inches — smooth to rough is 14.5 % on
        // diameter, two inches on a fourteen-inch duct. The bar is set just under the measured
        // spread so a regression that flattens the effect fails rather than merely narrowing it.
        let spread = (diameters.last! - diameters.first!) / diameters.first!
        #expect(spread > 0.13, "roughness spread is only \(spread * 100) %: \(diameters)")
    }

    @Test func roughnessValuesAreTheirPublishedCategories() {
        #expect(DuctRoughness.smooth.absoluteRoughness == 0.03e-3)
        #expect(DuctRoughness.mediumSmooth.absoluteRoughness == 0.09e-3)
        #expect(DuctRoughness.average.absoluteRoughness == 0.15e-3)
        #expect(DuctRoughness.mediumRough.absoluteRoughness == 0.9e-3)
        #expect(DuctRoughness.rough.absoluteRoughness == 3.0e-3)
        #expect(DuctRoughness.default == .mediumSmooth)
        #expect(DuctRoughness.allCases.allSatisfy { !$0.examples.isEmpty })
    }

    /// Altitude reaches the duct too: thinner air means less friction for the same volume flow,
    /// so a duct sized for Denver comes out smaller than the same job at sea level.
    @Test func altitudeChangesTheDuctSize() throws {
        let flow = 2000 * IP.cubicMetresPerCFM
        let target = 0.08 * IP.pascalsPerMetrePerInchWGPer100Feet
        let denverAir = AirProperties(density: AirProperties.standard.density * 0.823296)

        let seaLevel = try DuctSizing.diameter(flow: flow, frictionRate: target, air: .standard)
        let denver = try DuctSizing.diameter(flow: flow, frictionRate: target, air: denverAir)

        #expect(denver < seaLevel)
        #expect((seaLevel - denver) / seaLevel > 0.02, "altitude must move the answer visibly")
    }
}

@Suite("Round ⇄ rectangular")
struct RectangularTests {

    /// Published worked values of `De = 1.30 (ab)^0.625 / (a+b)^0.25`.
    @Test func equivalentDiameterMatchesTheEquation() throws {
        #expect(abs(try DuctSizing.equivalentDiameter(width: 14, height: 12) - 14.1585) < 1e-4)
        #expect(abs(try DuctSizing.equivalentDiameter(width: 12, height: 8) - 10.6563) < 1e-4)
        // A square duct's circular equivalent is slightly larger than its side.
        #expect(abs(try DuctSizing.equivalentDiameter(width: 10, height: 10) - 10.9317) < 1e-4)
    }

    /// The equation is dimensionally homogeneous, so it must give the same answer in any unit.
    @Test func unitsDoNotMatter() throws {
        let inches = try DuctSizing.equivalentDiameter(width: 14, height: 12)
        let millimetres = try DuctSizing.equivalentDiameter(width: 14 * 25.4, height: 12 * 25.4)
        #expect(abs(millimetres / 25.4 - inches) / inches < 1e-12)
    }

    /// The scaffold returned `0.85 × diameter` for the other side, which inverts nothing. This is
    /// the real inverse, and it must round-trip at every aspect ratio the trade uses.
    @Test func inverseRoundTripsForEveryAspectRatio() throws {
        for width in [6.0, 10, 14, 20, 30, 48] {
            for height in [4.0, 6, 8, 12, 20] {
                let de = try DuctSizing.equivalentDiameter(width: width, height: height)
                let back = try DuctSizing.rectangularSide(equivalentDiameter: de, knownSide: width)
                #expect(abs(back - height) / height < 1e-9,
                        "\(width)×\(height) → De \(de) → \(back)")
            }
        }
    }

    /// A rectangle always needs more sheet metal than the round duct it replaces — its perimeter
    /// is larger for the same friction. Worth asserting because it is the sanity check a user does
    /// in their head.
    @Test func aFlatterDuctNeedsMoreSide() throws {
        let de = 14.0
        let tall = try DuctSizing.rectangularSide(equivalentDiameter: de, knownSide: 12)
        let flat = try DuctSizing.rectangularSide(equivalentDiameter: de, knownSide: 6)
        #expect(flat > tall)
        #expect(6 + flat > 12 + tall, "the flatter duct has the larger perimeter")
    }
}

@Suite("Invalid duct input fails loudly")
struct DuctValidationTests {

    @Test func rejectsImpossibleGeometry() {
        #expect(throws: DuctError.invalidInput(name: "diameter", value: 0)) {
            try DuctSizing.velocity(flow: 1, diameter: 0)
        }
        #expect(throws: DuctError.invalidInput(name: "flow", value: -1)) {
            try DuctSizing.velocity(flow: -1, diameter: 0.3)
        }
        #expect(throws: DuctError.invalidInput(name: "width", value: -1)) {
            try DuctSizing.equivalentDiameter(width: -1, height: 10)
        }
    }

    @Test func rejectsImpossibleSizingRequests() {
        #expect(throws: DuctError.invalidInput(name: "friction rate", value: 0)) {
            try DuctSizing.diameter(flow: 0.5, frictionRate: 0)
        }
        #expect(throws: DuctError.invalidInput(name: "flow", value: 0)) {
            try DuctSizing.diameter(flow: 0, frictionRate: 0.8)
        }
        // A friction rate no duct in the search range can reach.
        #expect(throws: DuctError.noSolution(name: "this flow at this friction rate")) {
            try DuctSizing.diameter(flow: 100, frictionRate: 1e-9)
        }
    }

    @Test func rejectsNotANumber() {
        #expect(throws: (any Error).self) { try DuctSizing.velocity(flow: .nan, diameter: 0.3) }
        #expect(throws: (any Error).self) {
            try DuctSizing.frictionRate(flow: 0.5, diameter: .infinity)
        }
        #expect(throws: (any Error).self) {
            try DuctSizing.reynoldsNumber(velocity: 5, diameter: 0.3,
                                          air: AirProperties(density: 0))
        }
    }

    /// A closed damper is not an error: no flow, no velocity, no friction.
    @Test func zeroFlowIsAValidAnswer() throws {
        #expect(try DuctSizing.velocity(flow: 0, diameter: 0.3) == 0)
        #expect(try DuctSizing.frictionRate(flow: 0, diameter: 0.3) == 0)
    }

    /// The velocity default is the user's to change, and it is exactly 1,200 fpm.
    @Test func theVelocityDefaultIsTheTradeRuleOfThumb() {
        #expect(abs(DuctSizing.defaultVelocityLimit / IP.metresPerFootPerMinute - 1200) < 1e-9)
    }
}
