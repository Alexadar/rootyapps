import Testing
import Foundation
@testable import FluidKit

/// Oracle: the **Moody chart** — the published plot of Darcy friction factor against Reynolds
/// number and relative roughness that every fluids text prints, and the two analytic limits it is
/// bounded by (`f = 64/Re` laminar, von Kármán's fully-rough asymptote). Colebrook–White is the
/// correlation the chart's turbulent region is drawn from, so reproducing the chart's read-off
/// values and both asymptotes is what proves the implicit solve converged where it should.
@Suite("Friction factor against the Moody chart")
struct FrictionFactorTests {

    @Test func laminarFlowUsesTheLaminarLaw() throws {
        #expect(abs(try FluidFriction.darcyFrictionFactor(reynoldsNumber: 1000,
                                                          relativeRoughness: 0.001) - 0.064) < 1e-12)
        #expect(abs(try FluidFriction.darcyFrictionFactor(reynoldsNumber: 2000,
                                                          relativeRoughness: 0.001) - 0.032) < 1e-12)
        // Roughness does not matter in laminar flow — a result, not an implementation detail.
        let smooth = try FluidFriction.darcyFrictionFactor(reynoldsNumber: 1500,
                                                           relativeRoughness: 0)
        let rough = try FluidFriction.darcyFrictionFactor(reynoldsNumber: 1500,
                                                          relativeRoughness: 0.05)
        #expect(smooth == rough)
    }

    /// Smooth-pipe curve, read off the Moody chart.
    @Test func smoothPipeMatchesTheMoodyChart() throws {
        #expect(abs(try FluidFriction.darcyFrictionFactor(reynoldsNumber: 1e4,
                                                          relativeRoughness: 0) - 0.0309) < 5e-4)
        #expect(abs(try FluidFriction.darcyFrictionFactor(reynoldsNumber: 1e5,
                                                          relativeRoughness: 0) - 0.0180) < 5e-4)
        #expect(abs(try FluidFriction.darcyFrictionFactor(reynoldsNumber: 1e6,
                                                          relativeRoughness: 0) - 0.0116) < 5e-4)
        #expect(abs(try FluidFriction.darcyFrictionFactor(reynoldsNumber: 1e7,
                                                          relativeRoughness: 0) - 0.0081) < 5e-4)
    }

    /// The flat right-hand side of the chart: past a high enough Reynolds number the friction
    /// factor stops depending on it and settles on von Kármán's fully-rough value
    /// `1/√f = −2 log₁₀(ε/3.7D)`. If the Colebrook iteration were wrong this asymptote is the
    /// first thing that would break.
    @Test("Fully-rough flow reaches the von Kármán limit",
          arguments: [0.001, 0.005, 0.01, 0.03])
    func fullyRoughAsymptote(_ relativeRoughness: Double) throws {
        let f = try FluidFriction.darcyFrictionFactor(reynoldsNumber: 1e9,
                                                      relativeRoughness: relativeRoughness)
        let limit = 1 / pow(-2 * log10(relativeRoughness / 3.7), 2)
        #expect(abs(f - limit) / limit < 1e-3, "f \(f) vs limit \(limit)")

        let lower = try FluidFriction.darcyFrictionFactor(reynoldsNumber: 1e8,
                                                          relativeRoughness: relativeRoughness)
        #expect(abs(f - lower) / f < 0.01, "the factor must stop moving with Reynolds number")
    }

    /// The solved factor must actually satisfy Colebrook — checked by substituting back into the
    /// equation rather than by trusting the iteration to have converged.
    @Test func theSolutionSatisfiesColebrook() throws {
        for re in [5e3, 1e4, 1e5, 1e6, 1e7, 1e8] {
            for rr in [0.0, 1e-5, 1e-4, 1e-3, 1e-2] {
                let f = try FluidFriction.darcyFrictionFactor(reynoldsNumber: re,
                                                              relativeRoughness: rr)
                let lhs = 1 / f.squareRoot()
                let rhs = -2 * log10(rr / 3.7 + 2.51 / (re * f.squareRoot()))
                #expect(abs(lhs - rhs) / lhs < 1e-9,
                        "Re \(re), ε/D \(rr): 1/√f = \(lhs) but Colebrook says \(rhs)")
            }
        }
    }

    @Test func frictionFactorFallsWithReynoldsNumberAndRisesWithRoughness() throws {
        var previous = Double.infinity
        for exponent in stride(from: 4.0, through: 8.0, by: 0.5) {
            let f = try FluidFriction.darcyFrictionFactor(reynoldsNumber: pow(10, exponent),
                                                          relativeRoughness: 1e-4)
            #expect(f < previous)
            previous = f
        }
        var last = 0.0
        for rr in [0.0, 1e-5, 1e-4, 1e-3, 1e-2, 0.05] {
            let f = try FluidFriction.darcyFrictionFactor(reynoldsNumber: 1e6,
                                                          relativeRoughness: rr)
            #expect(f > last)
            last = f
        }
    }

    @Test func theTransitionalBandIsFlagged() {
        #expect(!FluidFriction.isTransitional(reynoldsNumber: 2000))
        #expect(FluidFriction.isTransitional(reynoldsNumber: 3000))
        #expect(!FluidFriction.isTransitional(reynoldsNumber: 5000))
    }
}

@Suite("Darcy–Weisbach")
struct PressureGradientTests {

    static let air = FluidFriction.Fluid(density: 1.2014693, dynamicViscosity: 1.825e-5)
    static let water = FluidFriction.Fluid(density: 998.2, dynamicViscosity: 1.002e-3)

    /// Hand-computed: 0.5 m/s of water in a 50 mm smooth pipe.
    /// Re = 998.2 × 0.5 × 0.05 / 1.002e-3 = 24,905; f ≈ 0.02465;
    /// Δp/L = 0.02465 × 998.2 × 0.25 / 0.1 = 61.5 Pa/m.
    @Test func handComputedWaterCase() throws {
        let diameter = 0.05
        let flow = 0.5 * (try FluidFriction.circularArea(diameter: diameter))
        let re = try FluidFriction.reynoldsNumber(velocity: 0.5, diameter: diameter,
                                                  fluid: Self.water)
        #expect(abs(re - 24_905) < 10, "got Re \(re)")

        let gradient = try FluidFriction.pressureGradient(volumeFlow: flow, diameter: diameter,
                                                          absoluteRoughness: 0, fluid: Self.water)
        #expect(abs(gradient - 61.5) < 0.5, "got \(gradient) Pa/m")
    }

    /// Doubling the velocity does **not** quadruple the loss, and the shortfall is exactly the
    /// friction factor falling as Reynolds number rises. Asserted as the identity
    /// `Δp₂/Δp₁ = 4 · f₂/f₁` rather than as a range, so it tests Darcy–Weisbach itself.
    ///
    /// Measured here: 3.65×, not 4×. A tool that assumed the square law would over-predict a
    /// doubled-flow duct by 9 %.
    @Test func scalesWithTheSquareOfVelocityTimesTheFrictionFactorRatio() throws {
        let diameter = 0.3, roughness = 1e-4
        let area = try FluidFriction.circularArea(diameter: diameter)

        func gradientAndFactor(_ velocity: Double) throws -> (gradient: Double, factor: Double) {
            let re = try FluidFriction.reynoldsNumber(velocity: velocity, diameter: diameter,
                                                      fluid: Self.air)
            return (try FluidFriction.pressureGradient(volumeFlow: velocity * area,
                                                       diameter: diameter,
                                                       absoluteRoughness: roughness,
                                                       fluid: Self.air),
                    try FluidFriction.darcyFrictionFactor(reynoldsNumber: re,
                                                          relativeRoughness: roughness / diameter))
        }

        let slow = try gradientAndFactor(5)
        let fast = try gradientAndFactor(10)
        let expected = 4 * fast.factor / slow.factor

        #expect(abs(fast.gradient / slow.gradient - expected) / expected < 1e-12)
        #expect(fast.gradient / slow.gradient < 4, "the square law is an over-estimate, always")
        #expect(abs(fast.gradient / slow.gradient - 3.651) < 0.01,
                "got \(fast.gradient / slow.gradient)")
    }

    @Test func sizingInvertsTheGradient() throws {
        for flow in [0.05, 0.5, 2.0] {
            for target in [0.5, 1.0, 5.0] {
                let d = try FluidFriction.diameter(volumeFlow: flow, pressureGradient: target,
                                                   absoluteRoughness: 9e-5, fluid: Self.air)
                let back = try FluidFriction.pressureGradient(volumeFlow: flow, diameter: d,
                                                              absoluteRoughness: 9e-5,
                                                              fluid: Self.air)
                #expect(abs(back - target) / target < 1e-9)
            }
        }
    }

    @Test func geometryRoundTrips() throws {
        for flow in [0.01, 1.0, 20.0] {
            let d = try FluidFriction.diameter(volumeFlow: flow, velocity: 3)
            #expect(abs(try FluidFriction.velocity(volumeFlow: flow, diameter: d) - 3) < 1e-12)
        }
    }

    @Test func noFlowIsNoFriction() throws {
        #expect(try FluidFriction.velocity(volumeFlow: 0, diameter: 0.1) == 0)
        #expect(try FluidFriction.pressureGradient(volumeFlow: 0, diameter: 0.1,
                                                   absoluteRoughness: 1e-4, fluid: Self.air) == 0)
    }

    @Test func rejectsImpossibleInput() {
        #expect(throws: FluidError.invalidInput(name: "diameter", value: 0)) {
            try FluidFriction.circularArea(diameter: 0)
        }
        #expect(throws: FluidError.invalidInput(name: "Reynolds number", value: 0)) {
            try FluidFriction.darcyFrictionFactor(reynoldsNumber: 0, relativeRoughness: 0)
        }
        #expect(throws: FluidError.invalidInput(name: "relative roughness", value: -1)) {
            try FluidFriction.darcyFrictionFactor(reynoldsNumber: 1e5, relativeRoughness: -1)
        }
        #expect(throws: FluidError.noSolution(name: "this flow at this pressure gradient")) {
            try FluidFriction.diameter(volumeFlow: 100, pressureGradient: 1e-12,
                                       absoluteRoughness: 1e-4, fluid: Self.air)
        }
        #expect(throws: (any Error).self) {
            try FluidFriction.velocity(volumeFlow: .nan, diameter: 0.1)
        }
    }

    @Test func kinematicViscosityIsDerived() {
        #expect(abs(Self.water.kinematicViscosity - 1.002e-3 / 998.2) < 1e-15)
    }
}
