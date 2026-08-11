import SwiftUI
import Observation
import PsychroKit
import UnitsKit

/// Two airstreams in, one state out — drawn on the chart between them.
///
/// ## Mass, not volume
///
/// The mixed state is weighted by the **dry-air mass flow** of each stream, not by CFM. The two are
/// only the same when the streams have the same density, which is exactly what they do not have in
/// the case this tool is for: 20 °F outdoor air against 75 °F return air differ by 11 %, and at
/// altitude the error compounds. 25 % outdoor air by volume is 24.2 % by mass, and the mixed dry
/// bulb lands about half a degree from where the shortcut puts it.
@Observable
final class MixingModel {

    private static let key = "AirCore.tool.mixing"

    var returnFlow: Double
    var returnDryBulb: Double
    var returnRelativeHumidity: Double
    var outdoorFlow: Double
    var outdoorDryBulb: Double
    var outdoorRelativeHumidity: Double

    init(returnFlow: Double = 7500 * 0.3048 * 0.3048 * 0.3048 / 60,
         returnDryBulb: Double = 23.888888888888889,       // 75 °F
         returnRelativeHumidity: Double = 0.5,
         outdoorFlow: Double = 2500 * 0.3048 * 0.3048 * 0.3048 / 60,
         outdoorDryBulb: Double = 35,                       // 95 °F
         outdoorRelativeHumidity: Double = 0.4) {
        self.returnFlow = returnFlow
        self.returnDryBulb = returnDryBulb
        self.returnRelativeHumidity = returnRelativeHumidity
        self.outdoorFlow = outdoorFlow
        self.outdoorDryBulb = outdoorDryBulb
        self.outdoorRelativeHumidity = outdoorRelativeHumidity
    }

    struct Solution {
        var returnAir: MoistAir
        var outdoorAir: MoistAir
        var mixed: MoistAir
        var outdoorMassFraction: Double
        var outdoorVolumeFraction: Double
    }

    func solved(pressure: Double) -> Result<Solution, Error> {
        do {
            let returnAir = try MoistAir(dryBulb: returnDryBulb,
                                         relativeHumidity: returnRelativeHumidity,
                                         pressure: pressure)
            let outdoorAir = try MoistAir(dryBulb: outdoorDryBulb,
                                          relativeHumidity: outdoorRelativeHumidity,
                                          pressure: pressure)
            let streams = [AirMixing.Stream(state: returnAir, volumeFlow: returnFlow),
                           AirMixing.Stream(state: outdoorAir, volumeFlow: outdoorFlow)]
            let mixed = try AirMixing.mix(streams)
            let totalVolume = returnFlow + outdoorFlow

            return .success(Solution(
                returnAir: returnAir, outdoorAir: outdoorAir, mixed: mixed,
                outdoorMassFraction: AirMixing.massFraction(of: streams[1], in: streams),
                outdoorVolumeFraction: totalVolume > 0 ? outdoorFlow / totalVolume : 0))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var returnFlow: Double
        var returnDryBulb: Double
        var returnRelativeHumidity: Double
        var outdoorFlow: Double
        var outdoorDryBulb: Double
        var outdoorRelativeHumidity: Double
    }

    func save() {
        Persistence.save(Snapshot(returnFlow: returnFlow, returnDryBulb: returnDryBulb,
                                  returnRelativeHumidity: returnRelativeHumidity,
                                  outdoorFlow: outdoorFlow, outdoorDryBulb: outdoorDryBulb,
                                  outdoorRelativeHumidity: outdoorRelativeHumidity),
                         key: Self.key)
    }

    static func loaded() -> MixingModel {
        guard let s = Persistence.load(Snapshot.self, key: key) else { return MixingModel() }
        return MixingModel(returnFlow: s.returnFlow, returnDryBulb: s.returnDryBulb,
                           returnRelativeHumidity: s.returnRelativeHumidity,
                           outdoorFlow: s.outdoorFlow, outdoorDryBulb: s.outdoorDryBulb,
                           outdoorRelativeHumidity: s.outdoorRelativeHumidity)
    }
}

struct MixingView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppModels.self) private var models
    @State private var showElevationSheet = false

    private var model: MixingModel { models.mixing }

    var body: some View {
        ToolScaffold(tool: .mixing, showElevationSheet: $showElevationSheet) {
            if case .success(let solution) = model.solved(pressure: settings.pressure) {
                PsychroChartView(points: [
                    ChartPoint(role: .a, state: solution.returnAir),
                    ChartPoint(role: .b, state: solution.outdoorAir),
                    ChartPoint(role: .mixed, state: solution.mixed),
                ], pressure: settings.pressure, system: settings.unitSystem, onDrag: nil)
                .frame(height: 200)
            }

            results

            stream(title: "RETURN AIR — A",
                   flow: Binding(get: { model.returnFlow }, set: { model.returnFlow = $0 }),
                   dryBulb: Binding(get: { model.returnDryBulb },
                                    set: { model.returnDryBulb = $0 }),
                   relativeHumidity: Binding(get: { model.returnRelativeHumidity },
                                             set: { model.returnRelativeHumidity = $0 }),
                   prefix: "return")

            stream(title: "OUTDOOR AIR — B",
                   flow: Binding(get: { model.outdoorFlow }, set: { model.outdoorFlow = $0 }),
                   dryBulb: Binding(get: { model.outdoorDryBulb },
                                    set: { model.outdoorDryBulb = $0 }),
                   relativeHumidity: Binding(get: { model.outdoorRelativeHumidity },
                                             set: { model.outdoorRelativeHumidity = $0 }),
                   prefix: "outdoor")
        }
    }

    private func stream(title: String, flow: Binding<Double>, dryBulb: Binding<Double>,
                        relativeHumidity: Binding<Double>, prefix: String) -> some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            Text(title)
                .font(DS.ui(10.5, .semibold)).tracking(1).foregroundStyle(DS.ink2)
            FieldPair {
                NumericField(title: "Flow", spokenTitle: "\(prefix) air flow", quantity: .airFlow,
                             system: settings.unitSystem, siValue: flow,
                             step: settings.unitSystem == .ip ? 250 : 100,
                             identifier: "\(prefix)Flow")
                NumericField(title: "Dry bulb", spokenTitle: "\(prefix) dry bulb",
                             quantity: .temperature, system: settings.unitSystem,
                             siValue: dryBulb, step: 0.5, identifier: "\(prefix)DryBulb")
                NumericField(title: "RH", spokenTitle: "\(prefix) relative humidity",
                             quantity: .relativeHumidity, system: settings.unitSystem,
                             siValue: relativeHumidity, step: 1, identifier: "\(prefix)RH")
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        switch model.solved(pressure: settings.pressure) {
        case .success(let solution):
            ResultGrid(tool: .mixing, rows: [
                .init(title: "Mixed dry bulb", value: solution.mixed.dryBulb,
                      quantity: .temperature, emphasised: true),
                .init(title: "Mixed wet bulb", value: solution.mixed.wetBulb,
                      quantity: .temperature, emphasised: true),
                .init(title: "Mixed RH", value: solution.mixed.relativeHumidity,
                      quantity: .relativeHumidity),
                .init(title: "Mixed humidity ratio", value: solution.mixed.humidityRatio,
                      quantity: .humidityRatio),
                .init(title: "Mixed enthalpy", value: solution.mixed.enthalpy,
                      quantity: .enthalpy),
                .init(title: "Outdoor air by mass", value: solution.outdoorMassFraction,
                      quantity: .relativeHumidity),
            ])

            let byVolume = solution.outdoorVolumeFraction
            let byMass = solution.outdoorMassFraction
            if abs(byVolume - byMass) > 0.002 {
                StatusBanner(
                    kind: .ok,
                    title: "Mixed on mass, not volume",
                    detail: "\(Fmt.number(byVolume * 100, decimals: 1)) % outdoor air by volume "
                          + "is \(Fmt.number(byMass * 100, decimals: 1)) % by mass, because the "
                          + "two streams are not the same density. The mixed state is weighted "
                          + "the second way.")
                .accessibilityIdentifier("mixing.massBanner")
            }
        case .failure(let error):
            if let psychro = error as? PsychroError, case .supersaturated = psychro {
                StatusBanner(kind: .warning, title: "These streams mix to fog",
                             detail: "The combined air is past saturation, so it would carry "
                                   + "liquid water rather than vapour. There is no moist-air "
                                   + "state to report.")
            } else {
                ErrorBanner(error: error)
            }
        }
    }
}
