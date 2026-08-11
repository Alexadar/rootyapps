import Testing
import Foundation
@testable import PipeKit

enum IP {
    static let cubicMetresPerGPM = 3.785411784e-3 / 60
    static let metresPerFoot = 0.3048
    static let metresPerInch = 0.0254
}

/// # The oracle, and its honest limits
///
/// Hazen–Williams is published in two forms — SI and IP — that are separate curve fits of the same
/// relation, so **each is an independent check on the other**. Where they agree, the implementation
/// is right; where they differ, that difference is the published fits' own disagreement, and it is
/// measured here rather than assumed away.
///
/// Darcy–Weisbach is checked in ``FluidKitTests`` against the Moody chart. What is checked here is
/// the water-side use of it: that head and pressure are the same statement, and that the two
/// methods bracket each other the way the literature says they do.
@Suite("Hazen–Williams")
struct HazenWilliamsTests {

    /// The IP form of Hazen–Williams: head loss in feet per 100 feet, flow in US gpm, bore in
    /// inches. A separate published fit from the SI form the Kit implements.
    static func ipHeadLossGradient(gpm: Double, inches: Double, coefficient c: Double) -> Double {
        let feetPer100Feet = 0.2083 * pow(100 / c, 1.852) * pow(gpm, 1.852) / pow(inches, 4.8655)
        return feetPer100Feet / 100        // ft/ft ≡ m/m
    }

    struct Case {
        let flowGPM: Double
        let boreInches: Double
        let coefficient: Double
    }

    static let cases: [Case] = [
        .init(flowGPM: 10, boreInches: 1, coefficient: 140),
        .init(flowGPM: 40, boreInches: 2, coefficient: 140),
        .init(flowGPM: 180, boreInches: 4, coefficient: 140),
        .init(flowGPM: 400, boreInches: 6, coefficient: 130),
        .init(flowGPM: 1585, boreInches: 11.811, coefficient: 130),
        .init(flowGPM: 90, boreInches: 3, coefficient: 100),
    ]

    /// The SI form this Kit implements and the published IP form agree to about 2 % — which is the
    /// two fits' disagreement, not an error in either. Asserting anything tighter would be
    /// claiming an agreement the published equations do not have.
    @Test("SI and IP forms agree to 2.5 %", arguments: cases)
    func siAndIPFormsAgree(_ test: Case) throws {
        let si = try PipeSizing.hazenWilliamsHeadLossGradient(
            flow: test.flowGPM * IP.cubicMetresPerGPM,
            innerDiameter: test.boreInches * IP.metresPerInch,
            coefficient: test.coefficient)
        let ip = Self.ipHeadLossGradient(gpm: test.flowGPM, inches: test.boreInches,
                                         coefficient: test.coefficient)
        #expect(abs(si - ip) / ip < 0.025,
                "\(test.flowGPM) gpm in \(test.boreInches)\": SI \(si) vs IP \(ip)")
    }

    /// A worked case from the literature: 0.1 m³/s through 300 mm cast iron at C = 130 loses
    /// 6.42 m of head per kilometre.
    @Test func publishedWorkedCase() throws {
        let gradient = try PipeSizing.hazenWilliamsHeadLossGradient(flow: 0.1, innerDiameter: 0.3,
                                                                    coefficient: 130)
        #expect(abs(gradient * 1000 - 6.423) < 0.01, "got \(gradient * 1000) m per km")
    }

    /// The exponents are the content of the equation, so they are asserted as exponents.
    @Test func exponentsAreThePublishedOnes() throws {
        let base = try PipeSizing.hazenWilliamsHeadLossGradient(flow: 0.01, innerDiameter: 0.05,
                                                                 coefficient: 140)
        // Flow: h ∝ Q^1.852
        let doubleFlow = try PipeSizing.hazenWilliamsHeadLossGradient(flow: 0.02,
                                                                      innerDiameter: 0.05,
                                                                      coefficient: 140)
        #expect(abs(doubleFlow / base - pow(2, 1.852)) / pow(2, 1.852) < 1e-12)
        // Diameter: h ∝ D^-4.8704
        let doubleBore = try PipeSizing.hazenWilliamsHeadLossGradient(flow: 0.01,
                                                                      innerDiameter: 0.1,
                                                                      coefficient: 140)
        #expect(abs(base / doubleBore - pow(2, 4.8704)) / pow(2, 4.8704) < 1e-12)
        // Coefficient: h ∝ C^-1.852
        let rougher = try PipeSizing.hazenWilliamsHeadLossGradient(flow: 0.01, innerDiameter: 0.05,
                                                                    coefficient: 70)
        #expect(abs(rougher / base - pow(2, 1.852)) / pow(2, 1.852) < 1e-12)
    }
}

@Suite("Darcy and Hazen–Williams disagree, by a measured amount")
struct MethodComparisonTests {

    /// Both methods are offered, so the app must be able to say how far apart they are. Measured
    /// for copper at design velocities: Hazen–Williams runs 2 % high at 15 mm and 20 % high at
    /// 200 mm, and it is **always** the higher of the two.
    ///
    /// This is the kind of thing that has to be a test rather than a comment: if the gap ever
    /// closed or inverted, one of the two implementations would have changed and the app would be
    /// quietly labelling numbers with the wrong method.
    @Test("Hazen–Williams is the conservative one",
          arguments: [(0.015, 3.0), (0.025, 10.0), (0.05, 40.0), (0.1, 180.0), (0.2, 700.0)])
    func hazenWilliamsIsConservative(_ bore: Double, _ gpm: Double) throws {
        let flow = gpm * IP.cubicMetresPerGPM
        let darcy = try PipeSizing.headLossGradient(flow: flow, innerDiameter: bore,
                                                    material: .copper)
        let hazen = try PipeSizing.hazenWilliamsHeadLossGradient(flow: flow, innerDiameter: bore,
                                                                  material: .copper)
        #expect(hazen > darcy, "at \(bore * 1000) mm: Darcy \(darcy), H–W \(hazen)")
        #expect(hazen / darcy < 1.25, "the gap must stay inside a quarter: got \(hazen / darcy)")
    }

    /// Hazen–Williams has no viscosity term, so it cannot see the difference between a chilled
    /// loop and a heating loop. Darcy can, and does — 20 % on head loss between 4 °C and 60 °C.
    /// A user choosing the simpler method should know what it is blind to.
    @Test func onlyDarcySeesWaterTemperature() throws {
        let flow = 40 * IP.cubicMetresPerGPM
        let bore = 0.05

        let chilled = try PipeSizing.headLossGradient(flow: flow, innerDiameter: bore,
                                                      material: .copper, water: .chilled)
        let heating = try PipeSizing.headLossGradient(flow: flow, innerDiameter: bore,
                                                      material: .copper, water: .heating)
        #expect(chilled > heating, "cold water is more viscous and costs more head")
        #expect((chilled - heating) / heating > 0.10,
                "the temperature effect must be visible: got \((chilled - heating) / heating)")

        // Hazen–Williams returns the same number either way, by construction.
        let hazenA = try PipeSizing.hazenWilliamsHeadLossGradient(flow: flow, innerDiameter: bore,
                                                                   material: .copper)
        #expect(hazenA > 0)
    }

    @Test func theMethodSwitchSelectsTheRightEquation() throws {
        let flow = 40 * IP.cubicMetresPerGPM
        let darcy = try PipeSizing.headLossGradient(flow: flow, innerDiameter: 0.05,
                                                    material: .copper, method: .darcyWeisbach)
        let hazen = try PipeSizing.headLossGradient(flow: flow, innerDiameter: 0.05,
                                                    material: .copper, method: .hazenWilliams)
        #expect(abs(darcy - (try PipeSizing.headLossGradient(flow: flow, innerDiameter: 0.05,
                                                             material: .copper))) < 1e-15)
        #expect(abs(hazen - (try PipeSizing.hazenWilliamsHeadLossGradient(
            flow: flow, innerDiameter: 0.05, material: .copper))) < 1e-15)
        #expect(darcy != hazen)
    }
}

@Suite("Pipe geometry, sizing and limits")
struct PipeSizingTests {

    /// Hand-checkable: 10 gpm through a 1-inch bore. 10 gpm = 6.309e-4 m³/s;
    /// area = 5.067e-4 m²; V = 1.245 m/s = 4.08 ft/s.
    @Test func velocityWorkedCase() throws {
        let v = try PipeSizing.velocity(flow: 10 * IP.cubicMetresPerGPM,
                                        innerDiameter: 1 * IP.metresPerInch)
        #expect(abs(v - 1.2453) < 1e-3, "got \(v) m/s")
        #expect(abs(v / IP.metresPerFoot - 4.085) < 0.005, "got \(v / IP.metresPerFoot) ft/s")
    }

    @Test func sizingInvertsHeadLoss() throws {
        for gpm in [5.0, 40, 200] {
            for target in [0.02, 0.05, 0.1] {
                let flow = gpm * IP.cubicMetresPerGPM
                let d = try PipeSizing.innerDiameter(flow: flow, headLossGradient: target,
                                                     material: .copper)
                let back = try PipeSizing.headLossGradient(flow: flow, innerDiameter: d,
                                                           material: .copper)
                #expect(abs(back - target) / target < 1e-9)
            }
        }
    }

    /// Head in metres of water and pressure in pascals are the same statement through ρgh.
    @Test func headAndPressureAreTheSameStatement() throws {
        let flow = 40 * IP.cubicMetresPerGPM
        let head = try PipeSizing.headLossGradient(flow: flow, innerDiameter: 0.05,
                                                   material: .copper)
        let pressure = try PipeSizing.pressureGradient(headLossGradient: head)
        #expect(abs(pressure - head * 998.2 * 9.80665) < 1e-9)
        // One metre of water is 9,789 Pa at 20 °C.
        #expect(abs(try PipeSizing.pressureGradient(headLossGradient: 1) - 9789.0) < 1.0)
    }

    /// The published copper erosion limits, and the minimum that keeps air moving.
    @Test func velocityLimitsAreThePublishedFigures() {
        #expect(abs(PipeSizing.VelocityLimits.coldWater.maximum / IP.metresPerFoot - 8) < 1e-12)
        #expect(abs(PipeSizing.VelocityLimits.hotWater.maximum / IP.metresPerFoot - 5) < 1e-12)
        #expect(abs(PipeSizing.VelocityLimits.coldWater.minimum / IP.metresPerFoot - 2) < 1e-12)

        #expect(PipeSizing.status(velocity: 0.3, limits: .coldWater) == .tooSlow)
        #expect(PipeSizing.status(velocity: 1.2, limits: .coldWater) == .inRange)
        #expect(PipeSizing.status(velocity: 3.0, limits: .coldWater) == .tooFast)
        // The same velocity is acceptable cold and erosive hot — the reason there are two limits.
        #expect(PipeSizing.status(velocity: 2.0, limits: .coldWater) == .inRange)
        #expect(PipeSizing.status(velocity: 2.0, limits: .hotWater) == .tooFast)
    }

    @Test func everyMaterialCarriesBothConstantsAndTheyAreOrdered() {
        for material in PipeMaterial.allCases {
            #expect(material.absoluteRoughness > 0)
            #expect(material.hazenWilliamsRange.contains(material.hazenWilliamsCoefficient),
                    "\(material) design C is outside its own published range")
        }
        // Smoother pipe: lower roughness, higher C. The two constants must not contradict.
        #expect(PipeMaterial.copper.absoluteRoughness < PipeMaterial.castIronOld.absoluteRoughness)
        #expect(PipeMaterial.copper.hazenWilliamsCoefficient
                    > PipeMaterial.castIronOld.hazenWilliamsCoefficient)
    }

    /// Material must change the answer — the same dead-toggle guard the duct side carries.
    ///
    /// The count is against the *distinct published constants*, not against the number of
    /// materials, because copper and plastic genuinely share a roughness (1.5 µm) while having
    /// different Hazen–Williams coefficients (140 and 150). Asserting seven distinct Darcy answers
    /// would be demanding a difference the published data does not claim.
    @Test func materialChangesTheHeadLoss() throws {
        let flow = 40 * IP.cubicMetresPerGPM
        func distinct(_ values: [Double]) -> Int { Set(values.map { ($0 * 1e9).rounded() }).count }

        let darcy = try PipeMaterial.allCases.map {
            try PipeSizing.headLossGradient(flow: flow, innerDiameter: 0.05, material: $0)
        }
        let hazen = try PipeMaterial.allCases.map {
            try PipeSizing.hazenWilliamsHeadLossGradient(flow: flow, innerDiameter: 0.05,
                                                          material: $0)
        }

        #expect(distinct(darcy) == Set(PipeMaterial.allCases.map(\.absoluteRoughness)).count,
                "Darcy answers: \(darcy)")
        #expect(distinct(hazen)
                    == Set(PipeMaterial.allCases.map(\.hazenWilliamsCoefficient)).count,
                "Hazen–Williams answers: \(hazen)")
        #expect(distinct(darcy) > 1 && distinct(hazen) > 1, "the material picker must do something")
    }
}

@Suite("Invalid pipe input fails loudly")
struct PipeValidationTests {

    @Test func rejectsImpossibleGeometry() {
        #expect(throws: PipeError.invalidInput(name: "inner diameter", value: 0)) {
            try PipeSizing.velocity(flow: 1e-3, innerDiameter: 0)
        }
        #expect(throws: PipeError.invalidInput(name: "inner diameter", value: 0)) {
            try PipeSizing.hazenWilliamsHeadLossGradient(flow: 1e-3, innerDiameter: 0,
                                                          coefficient: 140)
        }
        #expect(throws: PipeError.invalidInput(name: "Hazen–Williams coefficient", value: 0)) {
            try PipeSizing.hazenWilliamsHeadLossGradient(flow: 1e-3, innerDiameter: 0.05,
                                                          coefficient: 0)
        }
    }

    @Test func rejectsImpossibleSizingRequests() {
        #expect(throws: PipeError.invalidInput(name: "head loss gradient", value: 0)) {
            try PipeSizing.innerDiameter(flow: 1e-3, headLossGradient: 0)
        }
        #expect(throws: PipeError.noSolution(name: "this flow at this head loss")) {
            try PipeSizing.innerDiameter(flow: 10, headLossGradient: 1e-12)
        }
    }

    @Test func rejectsNotANumber() {
        #expect(throws: (any Error).self) {
            try PipeSizing.velocity(flow: .nan, innerDiameter: 0.05)
        }
        #expect(throws: (any Error).self) {
            try PipeSizing.headLossGradient(flow: 1e-3, innerDiameter: .infinity,
                                            material: .copper)
        }
    }

    @Test func noFlowIsNoLoss() throws {
        #expect(try PipeSizing.velocity(flow: 0, innerDiameter: 0.05) == 0)
        #expect(try PipeSizing.headLossGradient(flow: 0, innerDiameter: 0.05,
                                                material: .copper) == 0)
        #expect(try PipeSizing.hazenWilliamsHeadLossGradient(flow: 0, innerDiameter: 0.05,
                                                              coefficient: 140) == 0)
    }
}
