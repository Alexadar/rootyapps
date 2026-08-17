import SwiftUI
import Observation
import AltitudeKit
import FanKit
import PsychroKit
import UnitsKit

/// Fan affinity laws, with the density correction that is not optional.
///
/// ## The trap this screen exists to close
///
/// Flow does not change with density; pressure and power do. Move a fan to Denver and it still
/// shifts the same CFM, but it develops 18 % less static pressure and draws 18 % less power. Size a
/// motor on that thin-air figure and the same fan overloads it on a cold morning at sea level.
///
/// So this tool asks for two elevations, not one, and shows what changes between them.
@Observable
final class FanModel {

    private static let key = "AirCore.tool.fan"

    /// m³/s
    var flow: Double
    /// RPM
    var speed: Double
    /// Pa
    var pressure: Double
    /// W
    var power: Double
    /// RPM
    var newSpeed: Double
    /// Elevation the fan was rated at, m.
    var ratedElevation: Double
    /// Elevation it will run at, m.
    var installedElevation: Double
    /// Air temperature at each, °C.
    var airTemperature: Double

    init(flow: Double = 2000 * 0.3048 * 0.3048 * 0.3048 / 60,
         speed: Double = 1150,
         pressure: Double = 1.0 * 248.84,
         power: Double = 1.5 * 745.6998715822702,
         newSpeed: Double = 1400,
         ratedElevation: Double = 0,
         installedElevation: Double = 0,
         airTemperature: Double = 20) {
        self.flow = flow
        self.speed = speed
        self.pressure = pressure
        self.power = power
        self.newSpeed = newSpeed
        self.ratedElevation = ratedElevation
        self.installedElevation = installedElevation
        self.airTemperature = airTemperature
    }

    struct Solution {
        var flow: Double
        var pressure: Double
        var power: Double
        var speedRatio: Double
        var densityRatio: Double
        var ratedDensity: Double
        var installedDensity: Double
    }

    func solved() -> Result<Solution, Error> {
        do {
            let ratedDensity = try density(atElevation: ratedElevation)
            let installedDensity = try density(atElevation: installedElevation)

            return .success(Solution(
                flow: try FanLaws.flow(flow, fromSpeed: speed, toSpeed: newSpeed),
                pressure: try FanLaws.pressure(pressure, fromSpeed: speed, toSpeed: newSpeed,
                                               fromDensity: ratedDensity,
                                               toDensity: installedDensity),
                power: try FanLaws.power(power, fromSpeed: speed, toSpeed: newSpeed,
                                         fromDensity: ratedDensity,
                                         toDensity: installedDensity),
                speedRatio: try FanLaws.speedRatio(speed, newSpeed),
                densityRatio: try FanLaws.densityRatio(ratedDensity, installedDensity),
                ratedDensity: ratedDensity,
                installedDensity: installedDensity))
        } catch {
            return .failure(error)
        }
    }

    private func density(atElevation metres: Double) throws -> Double {
        let elevation = try Elevation(metres: metres)
        return try MoistAir(dryBulb: airTemperature, relativeHumidity: 0,
                            pressure: elevation.barometricPressure).density
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var flow: Double
        var speed: Double
        var pressure: Double
        var power: Double
        var newSpeed: Double
        var ratedElevation: Double
        var installedElevation: Double
        var airTemperature: Double
    }

    func save() {
        Persistence.save(Snapshot(flow: flow, speed: speed, pressure: pressure, power: power,
                                  newSpeed: newSpeed, ratedElevation: ratedElevation,
                                  installedElevation: installedElevation,
                                  airTemperature: airTemperature),
                         key: Self.key)
    }

    static func loaded() -> FanModel {
        guard let s = Persistence.load(Snapshot.self, key: key) else { return FanModel() }
        return FanModel(flow: s.flow, speed: s.speed, pressure: s.pressure, power: s.power,
                        newSpeed: s.newSpeed, ratedElevation: s.ratedElevation,
                        installedElevation: s.installedElevation,
                        airTemperature: s.airTemperature)
    }
}

struct FanView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppModels.self) private var models
    @State private var showElevationSheet = false

    private var model: FanModel { models.fan }

    var body: some View {
        ToolScaffold(tool: .fan, showElevationSheet: $showElevationSheet) {
            Text("AT THE RATED POINT")
                .font(DS.ui(10.5, .semibold)).tracking(1).foregroundStyle(DS.ink2)

            FieldPair {
                NumericField(title: "Air flow", spokenTitle: "Rated air flow", quantity: .airFlow,
                             system: settings.unitSystem,
                             siValue: Binding(get: { model.flow }, set: { model.flow = $0 }),
                             step: settings.unitSystem == .ip ? 50 : 25,
                             isActive: true, identifier: "fan.flow")
                NumericField(title: "Speed", spokenTitle: "Rated speed", quantity: .fanSpeed,
                             system: settings.unitSystem,
                             siValue: Binding(get: { model.speed }, set: { model.speed = $0 }),
                             step: 10, isActive: true, identifier: "fan.speed")
            }

            FieldPair {
                NumericField(title: "Static pressure", spokenTitle: "Rated static pressure",
                             quantity: .fanPressure, system: settings.unitSystem,
                             siValue: Binding(get: { model.pressure },
                                              set: { model.pressure = $0 }),
                             step: settings.unitSystem == .ip ? 0.1 : 10,
                             identifier: "fan.pressure")
                NumericField(title: "Shaft power", spokenTitle: "Rated shaft power",
                             quantity: .fanPower, system: settings.unitSystem,
                             siValue: Binding(get: { model.power }, set: { model.power = $0 }),
                             step: settings.unitSystem == .ip ? 0.25 : 0.2,
                             identifier: "fan.power")
            }

            Text("AT THE NEW POINT")
                .font(DS.ui(10.5, .semibold)).tracking(1).foregroundStyle(DS.ink2)
                .padding(.top, DS.s2)

            NumericField(title: "New speed", spokenTitle: "New speed", quantity: .fanSpeed,
                         system: settings.unitSystem,
                         siValue: Binding(get: { model.newSpeed }, set: { model.newSpeed = $0 }),
                         step: 10, isActive: true, identifier: "fan.newSpeed")

            FieldPair {
                NumericField(title: "Rated at elevation", spokenTitle: "Rated at elevation",
                             quantity: .elevation, system: settings.unitSystem,
                             siValue: Binding(get: { model.ratedElevation },
                                              set: { model.ratedElevation = $0 }),
                             step: settings.unitSystem == .ip ? 100 : 50,
                             identifier: "fan.ratedElevation")
                NumericField(title: "Installed at elevation",
                             spokenTitle: "Installed at elevation",
                             quantity: .elevation, system: settings.unitSystem,
                             siValue: Binding(get: { model.installedElevation },
                                              set: { model.installedElevation = $0 }),
                             step: settings.unitSystem == .ip ? 100 : 50,
                             identifier: "fan.installedElevation")
            }

            results
        }
    }

    @ViewBuilder
    private var results: some View {
        switch model.solved() {
        case .success(let solution):
            ResultGrid(tool: .fan, rows: [
                .init(title: "Air flow", value: solution.flow, quantity: .airFlow,
                      emphasised: true),
                .init(title: "Static pressure", value: solution.pressure, quantity: .fanPressure,
                      emphasised: true),
                .init(title: "Shaft power", value: solution.power, quantity: .fanPower,
                      emphasised: true),
                .init(title: "Speed ratio", value: solution.speedRatio, quantity: .dimensionless),
                .init(title: "Density ratio", value: solution.densityRatio,
                      quantity: .dimensionless),
                .init(title: "Installed density", value: solution.installedDensity,
                      quantity: .density),
            ])

            if abs(solution.densityRatio - 1) > 0.005 {
                StatusBanner(
                    kind: .warning,
                    title: "Density correction applied",
                    detail: "Flow is unchanged by density — pressure and power are not. "
                          + "At this elevation they are "
                          + "\(Fmt.number(solution.densityRatio * 100, decimals: 1)) % of the "
                          + "rated figures. A motor sized on the thinner air will overload in the "
                          + "denser air.")
                .accessibilityIdentifier("fan.densityBanner")
            }
        case .failure(let error):
            ErrorBanner(error: error)
        }
    }
}
