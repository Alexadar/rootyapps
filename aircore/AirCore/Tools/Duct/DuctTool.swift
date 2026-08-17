import SwiftUI
import Observation
import DuctKit
import PsychroKit
import UnitsKit

/// Straight duct from friction.
///
/// > This is not a duct *design* tool. There is no fitting library and no equivalent length,
/// > because that data is licensed. What this does is size a straight run and check what the air
/// > will sound like in it.
///
/// ## Lockable, because "what if" is the actual job
///
/// A duct is never sized once. The friction rate is a target, the ceiling height is a constraint,
/// and the flow is whatever the equipment needs — so the tool lets the user fix any two of
/// {flow, friction rate, diameter} and solve the third, and lock one side of a rectangle and solve
/// the other.
///
/// ## Density is not optional here either
///
/// The friction rate depends on the density of the air in the duct, so the elevation the rest of
/// the app is set to reaches this tool too. A run sized in Denver comes out smaller than the same
/// job at sea level, and the difference is visible.
@Observable
final class DuctModel {

    private static let key = "AirCore.tool.duct"

    enum Unknown: String, CaseIterable, Codable, Identifiable {
        case diameter, frictionRate, flow

        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .diameter:     return "Diameter"
            case .frictionRate: return "Friction"
            case .flow:         return "Flow"
            }
        }
    }

    var solveFor: Unknown
    /// m³/s
    var volumeFlow: Double
    /// Pa/m
    var frictionRate: Double
    /// m
    var diameter: Double
    var roughness: DuctRoughness
    /// One side of the rectangular equivalent, m.
    var rectangularSide: Double

    init(solveFor: Unknown = .diameter,
         volumeFlow: Double = 1000 * 0.3048 * 0.3048 * 0.3048 / 60,   // 1000 CFM
         frictionRate: Double = 0.1 * 248.84 / (100 * 0.3048),        // 0.1 in wg/100 ft
         diameter: Double = 14 * 0.0254,
         roughness: DuctRoughness = .default,
         rectangularSide: Double = 12 * 0.0254) {
        self.solveFor = solveFor
        self.volumeFlow = volumeFlow
        self.frictionRate = frictionRate
        self.diameter = diameter
        self.roughness = roughness
        self.rectangularSide = rectangularSide
    }

    struct Solution {
        var volumeFlow: Double
        var frictionRate: Double
        var diameter: Double
        var velocity: Double
        var equivalentOtherSide: Double?
    }

    func solved(pressure: Double, temperature: Double) -> Result<Solution, Error> {
        do {
            // The air in the duct, at the site's elevation. Dry air at the given temperature is
            // enough: humidity moves the density by well under a percent, and asking a technician
            // for a duct's humidity to size it would be theatre.
            let air = try MoistAir(dryBulb: temperature, relativeHumidity: 0, pressure: pressure)
            let properties = AirProperties(density: air.density)

            var flow = volumeFlow
            var friction = frictionRate
            var size = diameter

            switch solveFor {
            case .diameter:
                size = try DuctSizing.diameter(flow: flow, frictionRate: friction,
                                               roughness: roughness, air: properties)
            case .frictionRate:
                friction = try DuctSizing.frictionRate(flow: flow, diameter: size,
                                                       roughness: roughness, air: properties)
            case .flow:
                // No closed form: friction rises monotonically with flow at fixed diameter, so
                // bisect on flow the same way the Kit bisects on diameter.
                flow = try flowFor(frictionRate: friction, diameter: size, air: properties)
            }

            let velocity = try DuctSizing.velocity(flow: flow, diameter: size)
            let equivalent = try? DuctSizing.rectangularSide(equivalentDiameter: size,
                                                             knownSide: rectangularSide)
            return .success(Solution(volumeFlow: flow, frictionRate: friction, diameter: size,
                                     velocity: velocity, equivalentOtherSide: equivalent))
        } catch {
            return .failure(error)
        }
    }

    private func flowFor(frictionRate target: Double, diameter: Double,
                         air: AirProperties) throws -> Double {
        var low = 1e-6
        var high = 100.0
        for _ in 0..<200 {
            let mid = (low + high) / 2
            if mid == low || mid == high { break }
            let friction = try DuctSizing.frictionRate(flow: mid, diameter: diameter,
                                                       roughness: roughness, air: air)
            if friction < target { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var solveFor: Unknown
        var volumeFlow: Double
        var frictionRate: Double
        var diameter: Double
        var roughness: DuctRoughness
        var rectangularSide: Double
    }

    func save() {
        Persistence.save(Snapshot(solveFor: solveFor, volumeFlow: volumeFlow,
                                  frictionRate: frictionRate, diameter: diameter,
                                  roughness: roughness, rectangularSide: rectangularSide),
                         key: Self.key)
    }

    static func loaded() -> DuctModel {
        guard let s = Persistence.load(Snapshot.self, key: key) else { return DuctModel() }
        return DuctModel(solveFor: s.solveFor, volumeFlow: s.volumeFlow,
                         frictionRate: s.frictionRate, diameter: s.diameter,
                         roughness: s.roughness, rectangularSide: s.rectangularSide)
    }
}

extension DuctRoughness {
    var title: LocalizedStringKey {
        switch self {
        case .smooth:       return "Smooth"
        case .mediumSmooth: return "Medium smooth"
        case .average:      return "Average"
        case .mediumRough:  return "Medium rough"
        case .rough:        return "Rough"
        }
    }

    var plainTitle: String {
        switch self {
        case .smooth:       return "Smooth"
        case .mediumSmooth: return "Medium smooth"
        case .average:      return "Average"
        case .mediumRough:  return "Medium rough"
        case .rough:        return "Rough"
        }
    }
}

struct DuctView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppModels.self) private var models
    @State private var showElevationSheet = false

    private var model: DuctModel { models.duct }

    /// The air temperature duct friction is computed at. Supply air, not room air — and fixed
    /// rather than another field, because its effect on density is small and a technician sizing a
    /// duct does not have a fourth number to give.
    private let ductAirTemperature = 20.0

    var body: some View {
        ToolScaffold(tool: .duct, showElevationSheet: $showElevationSheet) {
            Picker("Solve for", selection: Binding(get: { model.solveFor },
                                                   set: { model.solveFor = $0 })) {
                ForEach(DuctModel.Unknown.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("duct.solveFor")

            FieldPair {
                if model.solveFor != .flow {
                    NumericField(title: "Air flow", spokenTitle: "Air flow", quantity: .airFlow,
                                 system: settings.unitSystem,
                                 siValue: Binding(get: { model.volumeFlow },
                                                  set: { model.volumeFlow = $0 }),
                                 step: settings.unitSystem == .ip ? 50 : 25,
                                 isActive: true, identifier: "duct.flow")
                }
                if model.solveFor != .frictionRate {
                    NumericField(title: "Friction rate", spokenTitle: "Friction rate",
                                 quantity: .ductFrictionRate, system: settings.unitSystem,
                                 siValue: Binding(get: { model.frictionRate },
                                                  set: { model.frictionRate = $0 }),
                                 step: settings.unitSystem == .ip ? 0.01 : 0.1,
                                 isActive: true, identifier: "duct.friction")
                }
                if model.solveFor != .diameter {
                    NumericField(title: "Diameter", spokenTitle: "Diameter", quantity: .ductSize,
                                 system: settings.unitSystem,
                                 siValue: Binding(get: { model.diameter },
                                                  set: { model.diameter = $0 }),
                                 step: settings.unitSystem == .ip ? 1 : 25,
                                 isActive: true, identifier: "duct.diameter")
                }
            }

            Picker("Duct surface", selection: Binding(get: { model.roughness },
                                                      set: { model.roughness = $0 })) {
                ForEach(DuctRoughness.allCases) { roughness in
                    Text(roughness.title).tag(roughness)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("duct.roughness")

            Text(model.roughness.examples.joined(separator: " · "))
                .font(DS.ui(11.5))
                .foregroundStyle(DS.ink2)

            NumericField(title: "Rectangular — known side",
                         spokenTitle: "Rectangular duct known side",
                         quantity: .ductSize, system: settings.unitSystem,
                         siValue: Binding(get: { model.rectangularSide },
                                          set: { model.rectangularSide = $0 }),
                         step: settings.unitSystem == .ip ? 1 : 25,
                         identifier: "duct.rectSide")

            results
        }
    }

    @ViewBuilder
    private var results: some View {
        switch model.solved(pressure: settings.pressure, temperature: ductAirTemperature) {
        case .success(let solution):
            ResultGrid(tool: .duct, rows: rows(for: solution))
            velocityBanner(solution.velocity)

        case .failure(let error):
            ErrorBanner(error: error)
        }
    }

    private func rows(for solution: DuctModel.Solution) -> [ResultGrid.Row] {
        var rows: [ResultGrid.Row] = [
            .init(title: "Diameter", value: solution.diameter, quantity: .ductSize,
                  emphasised: model.solveFor == .diameter),
            .init(title: "Velocity", value: solution.velocity, quantity: .airVelocity,
                  emphasised: true),
            .init(title: "Friction rate", value: solution.frictionRate,
                  quantity: .ductFrictionRate, emphasised: model.solveFor == .frictionRate),
            .init(title: "Air flow", value: solution.volumeFlow, quantity: .airFlow,
                  emphasised: model.solveFor == .flow),
        ]
        if let other = solution.equivalentOtherSide {
            rows.append(.init(title: "Rectangular — other side", value: other,
                              quantity: .ductSize))
        }
        return rows
    }

    /// The velocity check, against **the user's own limit**. There is no code limit embedded
    /// anywhere in this app: per-application velocity tables are published in licensed documents.
    private func velocityBanner(_ velocity: Double) -> some View {
        let limit = settings.ductVelocityLimit
        let over = velocity > limit
        return StatusBanner(
            kind: over ? .warning : .ok,
            title: over ? "Above your velocity limit" : "Within your velocity limit",
            detail: "\(Fmt.valueWithUnit(si: velocity, .airVelocity, settings.unitSystem)) "
                  + "against a limit of "
                  + "\(Fmt.valueWithUnit(si: limit, .airVelocity, settings.unitSystem)). "
                  + (over ? "Faster duct is noisier duct." : ""))
        .accessibilityIdentifier("duct.velocityBanner")
    }
}
