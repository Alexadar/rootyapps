import SwiftUI
import Observation
import HeatKit
import PsychroKit
import UnitsKit

/// Air-side heat: sensible, latent and total across a coil, and the flow needed to carry a load.
///
/// ## Two states in, three loads out
///
/// The tool takes the air entering and the air leaving, because that is what a technician has: two
/// readings from two probes. Everything else follows — the mass flow from the entering state's
/// specific volume, the sensible load from the temperature drop, the latent from the moisture
/// removed, the total from the enthalpy difference.
///
/// Sensible plus latent equals total, and it is asserted in ``HeatKit``'s suite rather than assumed
/// here: three numbers on one screen that do not add up is the fastest way to lose a user's trust.
@Observable
final class HeatModel {

    private static let key = "AirCore.tool.heat"

    enum Unknown: String, CaseIterable, Codable, Identifiable {
        /// Flow is known; find the loads.
        case load
        /// The total load is known; find the flow that carries it.
        case flow

        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .load: return "Loads"
            case .flow: return "Flow"
            }
        }
    }

    var solveFor: Unknown
    /// m³/s
    var volumeFlow: Double
    /// W — used when solving for flow.
    var totalLoad: Double
    var enteringDryBulb: Double
    var enteringRelativeHumidity: Double
    var leavingDryBulb: Double
    var leavingRelativeHumidity: Double

    init(solveFor: Unknown = .load,
         volumeFlow: Double = 1000 * 0.3048 * 0.3048 * 0.3048 / 60,   // 1000 CFM
         totalLoad: Double = 10_000,
         enteringDryBulb: Double = 26.666666666666668,                // 80 °F
         enteringRelativeHumidity: Double = 0.5,
         leavingDryBulb: Double = 12.777777777777779,                 // 55 °F
         leavingRelativeHumidity: Double = 0.95) {
        self.solveFor = solveFor
        self.volumeFlow = volumeFlow
        self.totalLoad = totalLoad
        self.enteringDryBulb = enteringDryBulb
        self.enteringRelativeHumidity = enteringRelativeHumidity
        self.leavingDryBulb = leavingDryBulb
        self.leavingRelativeHumidity = leavingRelativeHumidity
    }

    struct Solution {
        var entering: MoistAir
        var leaving: MoistAir
        var massFlow: Double
        var volumeFlow: Double
        var sensible: Double
        var latent: Double
        var total: Double
        var sensibleHeatRatio: Double
    }

    func solved(pressure: Double) -> Result<Solution, Error> {
        do {
            let entering = try MoistAir(dryBulb: enteringDryBulb,
                                        relativeHumidity: enteringRelativeHumidity,
                                        pressure: pressure)
            let leaving = try MoistAir(dryBulb: leavingDryBulb,
                                       relativeHumidity: leavingRelativeHumidity,
                                       pressure: pressure)
            let enthalpyDrop = entering.enthalpy - leaving.enthalpy

            let mass: Double
            let volume: Double
            switch solveFor {
            case .load:
                mass = try AirSideHeat.dryAirMassFlow(volumeFlow: volumeFlow,
                                                      specificVolume: entering.specificVolume)
                volume = volumeFlow
            case .flow:
                mass = try AirSideHeat.dryAirMassFlow(totalHeat: totalLoad,
                                                      enthalpyDifference: enthalpyDrop)
                volume = mass * entering.specificVolume
            }

            let meanHumidity = (entering.humidityRatio + leaving.humidityRatio) / 2
            let sensible = try AirSideHeat.sensibleHeat(
                dryAirMassFlow: mass, humidityRatio: meanHumidity,
                temperatureDifference: entering.dryBulb - leaving.dryBulb)
            let latent = try AirSideHeat.latentHeat(
                dryAirMassFlow: mass,
                humidityRatioDifference: entering.humidityRatio - leaving.humidityRatio,
                meanDryBulb: (entering.dryBulb + leaving.dryBulb) / 2)
            let total = try AirSideHeat.totalHeat(dryAirMassFlow: mass,
                                                  enthalpyDifference: enthalpyDrop)

            return .success(Solution(
                entering: entering, leaving: leaving, massFlow: mass, volumeFlow: volume,
                sensible: sensible, latent: latent, total: total,
                sensibleHeatRatio: try AirSideHeat.sensibleHeatRatio(sensible: sensible,
                                                                     total: total)))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var solveFor: Unknown
        var volumeFlow: Double
        var totalLoad: Double
        var enteringDryBulb: Double
        var enteringRelativeHumidity: Double
        var leavingDryBulb: Double
        var leavingRelativeHumidity: Double
    }

    func save() {
        Persistence.save(Snapshot(solveFor: solveFor, volumeFlow: volumeFlow,
                                  totalLoad: totalLoad, enteringDryBulb: enteringDryBulb,
                                  enteringRelativeHumidity: enteringRelativeHumidity,
                                  leavingDryBulb: leavingDryBulb,
                                  leavingRelativeHumidity: leavingRelativeHumidity),
                         key: Self.key)
    }

    static func loaded() -> HeatModel {
        guard let s = Persistence.load(Snapshot.self, key: key) else { return HeatModel() }
        return HeatModel(solveFor: s.solveFor, volumeFlow: s.volumeFlow, totalLoad: s.totalLoad,
                         enteringDryBulb: s.enteringDryBulb,
                         enteringRelativeHumidity: s.enteringRelativeHumidity,
                         leavingDryBulb: s.leavingDryBulb,
                         leavingRelativeHumidity: s.leavingRelativeHumidity)
    }
}

struct HeatView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppModels.self) private var models
    @State private var showElevationSheet = false

    private var model: HeatModel { models.heat }

    var body: some View {
        ToolScaffold(tool: .airsideHeat, showElevationSheet: $showElevationSheet) {
            Picker("Solve for", selection: Binding(get: { model.solveFor },
                                                   set: { model.solveFor = $0 })) {
                ForEach(HeatModel.Unknown.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("airsideHeat.solveFor")

            if model.solveFor == .load {
                NumericField(title: "Air flow", spokenTitle: "Air flow", quantity: .airFlow,
                             system: settings.unitSystem,
                             siValue: Binding(get: { model.volumeFlow },
                                              set: { model.volumeFlow = $0 }),
                             step: settings.unitSystem == .ip ? 50 : 25,
                             isActive: true, identifier: "airsideHeat.flow")
            } else {
                NumericField(title: "Total load", spokenTitle: "Total load", quantity: .heatLoad,
                             system: settings.unitSystem,
                             siValue: Binding(get: { model.totalLoad },
                                              set: { model.totalLoad = $0 }),
                             step: settings.unitSystem == .ip ? 1000 : 250,
                             isActive: true, identifier: "airsideHeat.load")
            }

            FieldPair {
                NumericField(title: "Entering dry bulb", spokenTitle: "Entering dry bulb",
                             quantity: .temperature, system: settings.unitSystem,
                             siValue: Binding(get: { model.enteringDryBulb },
                                              set: { model.enteringDryBulb = $0 }),
                             step: 0.5, identifier: "airsideHeat.enteringDryBulb")
                NumericField(title: "Entering RH", spokenTitle: "Entering relative humidity",
                             quantity: .relativeHumidity, system: settings.unitSystem,
                             siValue: Binding(get: { model.enteringRelativeHumidity },
                                              set: { model.enteringRelativeHumidity = $0 }),
                             step: 1, identifier: "airsideHeat.enteringRH")
            }

            FieldPair {
                NumericField(title: "Leaving dry bulb", spokenTitle: "Leaving dry bulb",
                             quantity: .temperature, system: settings.unitSystem,
                             siValue: Binding(get: { model.leavingDryBulb },
                                              set: { model.leavingDryBulb = $0 }),
                             step: 0.5, identifier: "airsideHeat.leavingDryBulb")
                NumericField(title: "Leaving RH", spokenTitle: "Leaving relative humidity",
                             quantity: .relativeHumidity, system: settings.unitSystem,
                             siValue: Binding(get: { model.leavingRelativeHumidity },
                                              set: { model.leavingRelativeHumidity = $0 }),
                             step: 1, identifier: "airsideHeat.leavingRH")
            }

            results
        }
    }

    @ViewBuilder
    private var results: some View {
        switch model.solved(pressure: settings.pressure) {
        case .success(let solution):
            ResultGrid(tool: .airsideHeat, rows: [
                .init(title: "Sensible", value: solution.sensible, quantity: .heatLoad,
                      emphasised: true),
                .init(title: "Latent", value: solution.latent, quantity: .heatLoad),
                .init(title: "Total", value: solution.total, quantity: .heatLoad,
                      emphasised: true),
                .init(title: "Sensible heat ratio", value: solution.sensibleHeatRatio,
                      quantity: .dimensionless),
                .init(title: "Air flow", value: solution.volumeFlow, quantity: .airFlow,
                      emphasised: model.solveFor == .flow),
                .init(title: "Entering density", value: solution.entering.density,
                      quantity: .density),
            ])

            if solution.total < 0 {
                StatusBanner(kind: .warning, title: "This is a heating process",
                             detail: "The air leaves warmer than it entered, so the loads are "
                                   + "negative — the coil is adding heat, not removing it.")
            }
        case .failure(let error):
            ErrorBanner(error: error)
        }
    }
}
