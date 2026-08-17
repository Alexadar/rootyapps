import Testing
import Foundation
@testable import HeatKit

/// Conversion factors used only to express results in the units the published constants are
/// printed in. All exact by definition (NIST SP 811).
enum IP {
    static let cubicMetresPerCFM = (0.3048 * 0.3048 * 0.3048) / 60
    static let wattsPerBtuPerHour = 1055.05585262 / 3600
    static let kelvinPerFahrenheitDegree = 1 / 1.8
    static let kilojoulesPerKilogramPerBtuPerPound = 2.326

    /// Standard air: 0.075 lb/ft³, i.e. 13.333 ft³ per pound, expressed as m³/kg.
    static let standardAirSpecificVolume = (1 / 0.075) * (0.3048 * 0.3048 * 0.3048) / 0.45359237

    /// W per (m³/s) per K  →  Btu/h per CFM per °F. This is the "1.08" scale.
    static func sensibleConstant(_ si: Double) -> Double {
        si * cubicMetresPerCFM * kelvinPerFahrenheitDegree / wattsPerBtuPerHour
    }
    /// W per (m³/s) per (kg/kg)  →  Btu/h per CFM per (lb/lb). The "4840" scale — the humidity
    /// ratio is dimensionless, so only flow and power convert.
    static func latentConstant(_ si: Double) -> Double {
        si * cubicMetresPerCFM / wattsPerBtuPerHour
    }
    /// W per (m³/s) per (kJ/kg)  →  Btu/h per CFM per (Btu/lb). The "4.5" scale.
    static func totalConstant(_ si: Double) -> Double {
        si * cubicMetresPerCFM * kilojoulesPerKilogramPerBtuPerPound / wattsPerBtuPerHour
    }
}

/// The oracle here is the trade's own published constants — 1.08, 4840 and 4.5 — which are not
/// independent numbers but consequences of standard air. Recovering all three from the SI
/// relations, to better than the precision they are printed at, is the proof that this Kit and the
/// field rule of thumb are the same physics.
@Suite("Air-side heat against the published field constants")
struct AirSideHeatOracleTests {

    @Test func recoversTheSensibleConstant() throws {
        let si = try AirSideHeat.sensibleConstantPerVolumeFlow(
            specificVolume: IP.standardAirSpecificVolume, humidityRatio: 0)
        #expect(abs(IP.sensibleConstant(si) - 1.08) < 0.005,
                "got \(IP.sensibleConstant(si)), the trade prints 1.08")
    }

    @Test func recoversTheLatentConstant() throws {
        let si = try AirSideHeat.latentConstantPerVolumeFlow(
            specificVolume: IP.standardAirSpecificVolume, meanDryBulb: 0)
        #expect(abs(IP.latentConstant(si) - 4840) < 5,
                "got \(IP.latentConstant(si)), the trade prints 4840")
    }

    @Test func recoversTheTotalConstant() throws {
        let si = try AirSideHeat.totalConstantPerVolumeFlow(
            specificVolume: IP.standardAirSpecificVolume)
        #expect(abs(IP.totalConstant(si) - 4.5) < 0.005,
                "got \(IP.totalConstant(si)), the trade prints 4.5")
    }

    /// **The reason this Kit exists.** At Denver the sensible constant is 0.89, not 1.08 — an 18 %
    /// error if the sea-level value is used, on every duct, every coil and every fan.
    @Test func theSensibleConstantIsWrongAtAltitudeAndThisKitKnowsIt() throws {
        // Same air, same temperature, Denver's pressure: specific volume scales with 1/pressure.
        let denverVolume = IP.standardAirSpecificVolume / 0.823296
        let si = try AirSideHeat.sensibleConstantPerVolumeFlow(specificVolume: denverVolume,
                                                              humidityRatio: 0)
        let constant = IP.sensibleConstant(si)
        #expect(abs(constant - 0.89) < 0.005, "got \(constant), the trade prints ≈0.89 for Denver")
        #expect(constant < 1.08 * 0.85, "the altitude correction must be a large effect, not a nudge")
    }

    /// The trade prints both 1.08 and 1.10 for the same constant, and both are defensible: 1.08
    /// pairs dry-air specific heat with dry-air density, 1.10 pairs *moist*-air specific heat with
    /// the same dry-air density. The 1.7 % gap is the moisture in the air. This Kit sidesteps the
    /// argument by taking the specific heat and the density of the air that is actually there.
    @Test func theOnePointTenVariantIsTheMoistSpecificHeat() throws {
        let dry = try AirSideHeat.sensibleConstantPerVolumeFlow(
            specificVolume: IP.standardAirSpecificVolume, humidityRatio: 0)
        let moist = try AirSideHeat.sensibleConstantPerVolumeFlow(
            specificVolume: IP.standardAirSpecificVolume, humidityRatio: 0.009277)
        #expect(abs(IP.sensibleConstant(dry) - 1.08) < 0.005)
        #expect(abs(IP.sensibleConstant(moist) - 1.10) < 0.005)
    }

    /// A worked case in IP, computed entirely in SI: 1,000 CFM of standard air across a 20 °F rise.
    /// The rule of thumb says 1.08 × 1000 × 20 = 21,600 Btu/h.
    @Test func workedCaseInIP() throws {
        let massFlow = try AirSideHeat.dryAirMassFlow(volumeFlow: 1000 * IP.cubicMetresPerCFM,
                                                      specificVolume: IP.standardAirSpecificVolume)
        let watts = try AirSideHeat.sensibleHeat(dryAirMassFlow: massFlow, humidityRatio: 0,
                                                 temperatureDifference: 20 * IP.kelvinPerFahrenheitDegree)
        let btuPerHour = watts / IP.wattsPerBtuPerHour
        #expect(abs(btuPerHour - 21_600) < 50, "got \(btuPerHour) Btu/h")
    }

    /// The same case in SI, hand-computed: 0.4719474 m³/s ÷ 0.8323728 m³/kg = 0.5669905 kg/s;
    /// × 1.006 kJ/(kg·K) × 11.1111 K = 6.3377 kW.
    @Test func workedCaseInSI() throws {
        let massFlow = try AirSideHeat.dryAirMassFlow(volumeFlow: 0.4719474432,
                                                      specificVolume: 0.8323728076819283)
        #expect(abs(massFlow - 0.5669904625) < 1e-9, "got \(massFlow) kg/s")
        let watts = try AirSideHeat.sensibleHeat(dryAirMassFlow: massFlow, humidityRatio: 0,
                                                 temperatureDifference: 11.1111111)
        #expect(abs(watts - 6337.693) < 0.01, "got \(watts) W")
    }

    @Test func specificHeatAndVaporisationEnthalpy() throws {
        #expect(abs(try AirSideHeat.specificHeat(humidityRatio: 0) - 1.006) < 1e-12)
        #expect(abs(try AirSideHeat.specificHeat(humidityRatio: 0.01) - 1.0246) < 1e-9)
        #expect(abs(try AirSideHeat.vaporisationEnthalpy(dryBulb: 0) - 2501) < 1e-12)
        #expect(abs(try AirSideHeat.vaporisationEnthalpy(dryBulb: 25) - 2547.5) < 1e-9)
    }
}

/// "Solve in any direction" is a stated feature, so every inverse is walked back to its input.
@Suite("Solving in any direction")
struct InverseTests {

    static let massFlow = 0.5670972
    static let humidityRatio = 0.009277
    static let deltaT = 11.1111111

    @Test func sensibleInverses() throws {
        let q = try AirSideHeat.sensibleHeat(dryAirMassFlow: Self.massFlow,
                                             humidityRatio: Self.humidityRatio,
                                             temperatureDifference: Self.deltaT)
        let flowBack = try AirSideHeat.dryAirMassFlow(sensibleHeat: q,
                                                      humidityRatio: Self.humidityRatio,
                                                      temperatureDifference: Self.deltaT)
        let deltaBack = try AirSideHeat.temperatureDifference(sensibleHeat: q,
                                                              dryAirMassFlow: Self.massFlow,
                                                              humidityRatio: Self.humidityRatio)
        #expect(abs(flowBack - Self.massFlow) / Self.massFlow < 1e-12)
        #expect(abs(deltaBack - Self.deltaT) / Self.deltaT < 1e-12)
    }

    @Test func totalInverses() throws {
        let q = try AirSideHeat.totalHeat(dryAirMassFlow: Self.massFlow, enthalpyDifference: 12.5)
        #expect(abs(try AirSideHeat.dryAirMassFlow(totalHeat: q, enthalpyDifference: 12.5)
                        - Self.massFlow) / Self.massFlow < 1e-12)
        #expect(abs(try AirSideHeat.enthalpyDifference(totalHeat: q, dryAirMassFlow: Self.massFlow)
                        - 12.5) / 12.5 < 1e-12)
    }

    @Test func latentInverses() throws {
        let q = try AirSideHeat.latentHeat(dryAirMassFlow: Self.massFlow,
                                           humidityRatioDifference: 0.002, meanDryBulb: 12)
        let back = try AirSideHeat.humidityRatioDifference(latentHeat: q,
                                                           dryAirMassFlow: Self.massFlow,
                                                           meanDryBulb: 12)
        #expect(abs(back - 0.002) / 0.002 < 1e-12)
    }

    /// Sensible plus latent must equal total for the same two states, or the three tools on screen
    /// contradict each other.
    @Test func sensiblePlusLatentEqualsTotal() throws {
        // Cooling 27 °C / W 0.012 down to 13 °C / W 0.009 — a coil doing both jobs.
        let m = 0.6
        let (t1, w1) = (27.0, 0.012)
        let (t2, w2) = (13.0, 0.009)
        let meanT = (t1 + t2) / 2

        let sensible = try AirSideHeat.sensibleHeat(dryAirMassFlow: m, humidityRatio: (w1 + w2) / 2,
                                                    temperatureDifference: t1 - t2)
        let latent = try AirSideHeat.latentHeat(dryAirMassFlow: m,
                                                humidityRatioDifference: w1 - w2,
                                                meanDryBulb: meanT)
        // Total from the enthalpy difference of the same two states.
        let h1 = 1.006 * t1 + w1 * (2501 + 1.86 * t1)
        let h2 = 1.006 * t2 + w2 * (2501 + 1.86 * t2)
        let total = try AirSideHeat.totalHeat(dryAirMassFlow: m, enthalpyDifference: h1 - h2)

        #expect(abs(sensible + latent - total) / total < 0.005,
                "sensible \(sensible) + latent \(latent) vs total \(total)")

        let shr = try AirSideHeat.sensibleHeatRatio(sensible: sensible, total: total)
        #expect(shr > 0.5 && shr < 0.7, "a realistic coil SHR, got \(shr)")
    }
}

@Suite("Invalid input fails loudly")
struct HeatValidationTests {

    @Test func zeroDeltaCannotBeSolvedFor() {
        #expect(throws: HeatError.indeterminate(name: "ΔT")) {
            try AirSideHeat.dryAirMassFlow(sensibleHeat: 5000, humidityRatio: 0,
                                           temperatureDifference: 0)
        }
        #expect(throws: HeatError.indeterminate(name: "mass flow")) {
            try AirSideHeat.temperatureDifference(sensibleHeat: 5000, dryAirMassFlow: 0,
                                                  humidityRatio: 0)
        }
        #expect(throws: HeatError.indeterminate(name: "Δh")) {
            try AirSideHeat.dryAirMassFlow(totalHeat: 5000, enthalpyDifference: 0)
        }
        #expect(throws: HeatError.indeterminate(name: "total heat")) {
            try AirSideHeat.sensibleHeatRatio(sensible: 100, total: 0)
        }
    }

    @Test func rejectsImpossibleQuantities() {
        #expect(throws: HeatError.invalidInput(name: "mass flow", value: -1)) {
            try AirSideHeat.sensibleHeat(dryAirMassFlow: -1, humidityRatio: 0,
                                         temperatureDifference: 10)
        }
        #expect(throws: HeatError.invalidInput(name: "humidity ratio", value: -0.01)) {
            try AirSideHeat.specificHeat(humidityRatio: -0.01)
        }
        #expect(throws: HeatError.invalidInput(name: "specific volume", value: 0)) {
            try AirSideHeat.dryAirMassFlow(volumeFlow: 1, specificVolume: 0)
        }
    }

    @Test func rejectsNotANumber() {
        #expect(throws: (any Error).self) {
            try AirSideHeat.sensibleHeat(dryAirMassFlow: .nan, humidityRatio: 0,
                                         temperatureDifference: 10)
        }
        #expect(throws: (any Error).self) {
            try AirSideHeat.sensibleHeat(dryAirMassFlow: 1, humidityRatio: 0,
                                         temperatureDifference: .infinity)
        }
    }
}
