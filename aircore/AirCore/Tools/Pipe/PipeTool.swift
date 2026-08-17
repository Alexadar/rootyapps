import SwiftUI
import Observation
import PipeKit
import UnitsKit

/// Water pipe: head loss, velocity, and the limits that matter.
///
/// ## Two methods, and the app says which
///
/// Darcy–Weisbach and Hazen–Williams are both legitimate and they do **not** agree — measured for
/// copper across the small-bore range, Hazen–Williams runs 2 % high at 15 mm and 20 % high at
/// 200 mm. A tool that quietly picked one would be handing over a number that is 15 % different
/// from the one in the user's reference book with no explanation. So the method is a visible
/// choice, and the other method's answer is shown beside it.
@Observable
final class PipeModel {

    private static let key = "AirCore.tool.pipe"

    enum Unknown: String, CaseIterable, Codable, Identifiable {
        case headLoss, bore

        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .headLoss: return "Head loss"
            case .bore:     return "Bore"
            }
        }
    }

    var solveFor: Unknown
    /// m³/s
    var flow: Double
    /// m
    var bore: Double
    /// Pa/m — the target when solving for bore.
    var targetGradient: Double
    var material: PipeMaterial
    var method: HeadLossMethod

    init(solveFor: Unknown = .headLoss,
         flow: Double = 40 * 3.785411784e-3 / 60,      // 40 GPM
         bore: Double = 0.05,
         targetGradient: Double = 4 * 1000 * 9.80665 / 100,   // 4 ft head per 100 ft
         material: PipeMaterial = .copper,
         method: HeadLossMethod = .darcyWeisbach) {
        self.solveFor = solveFor
        self.flow = flow
        self.bore = bore
        self.targetGradient = targetGradient
        self.material = material
        self.method = method
    }

    struct Solution {
        var bore: Double
        var velocity: Double
        /// Pa/m by the selected method.
        var gradient: Double
        /// Pa/m by the other method, for comparison.
        var otherGradient: Double
        var status: PipeSizing.VelocityStatus
    }

    func solved(water: WaterProperties, limits: PipeSizing.VelocityLimits) -> Result<Solution, Error> {
        do {
            var size = bore
            if solveFor == .bore {
                // Darcy sizes the pipe whichever method is selected for reporting: Hazen–Williams
                // has no closed inverse worth trusting outside its fitted band, and a bore is a
                // decision, not a reading.
                size = try PipeSizing.innerDiameter(
                    flow: flow,
                    headLossGradient: targetGradient / (water.density * PipeSizing.standardGravity),
                    material: material, water: water)
            }

            let velocity = try PipeSizing.velocity(flow: flow, innerDiameter: size)
            func gradient(_ method: HeadLossMethod) throws -> Double {
                try PipeSizing.pressureGradient(
                    headLossGradient: try PipeSizing.headLossGradient(
                        flow: flow, innerDiameter: size, material: material,
                        water: water, method: method),
                    water: water)
            }

            return .success(Solution(
                bore: size, velocity: velocity,
                gradient: try gradient(method),
                otherGradient: try gradient(method == .darcyWeisbach ? .hazenWilliams
                                                                    : .darcyWeisbach),
                status: PipeSizing.status(velocity: velocity, limits: limits)))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var solveFor: Unknown
        var flow: Double
        var bore: Double
        var targetGradient: Double
        var material: PipeMaterial
        var method: HeadLossMethod
    }

    func save() {
        Persistence.save(Snapshot(solveFor: solveFor, flow: flow, bore: bore,
                                  targetGradient: targetGradient, material: material,
                                  method: method),
                         key: Self.key)
    }

    static func loaded() -> PipeModel {
        guard let s = Persistence.load(Snapshot.self, key: key) else { return PipeModel() }
        return PipeModel(solveFor: s.solveFor, flow: s.flow, bore: s.bore,
                         targetGradient: s.targetGradient, material: s.material,
                         method: s.method)
    }
}

extension PipeMaterial {
    var title: LocalizedStringKey {
        switch self {
        case .copper:         return "Copper"
        case .plastic:        return "Plastic (PVC, PEX)"
        case .steel:          return "Steel, new"
        case .steelAged:      return "Steel, aged"
        case .galvanizedIron: return "Galvanized iron"
        case .castIron:       return "Cast iron, new"
        case .castIronOld:    return "Cast iron, old"
        }
    }
}

extension HeadLossMethod {
    var title: LocalizedStringKey {
        switch self {
        case .darcyWeisbach: return "Darcy"
        case .hazenWilliams: return "Hazen–Williams"
        }
    }

    var other: HeadLossMethod {
        self == .darcyWeisbach ? .hazenWilliams : .darcyWeisbach
    }
}

struct PipeView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AppModels.self) private var models
    @State private var showElevationSheet = false

    private var model: PipeModel { models.pipe }
    private var water: WaterProperties { settings.waterIsHot ? .heating : .standard }
    private var limits: PipeSizing.VelocityLimits {
        settings.waterIsHot ? .hotWater : .coldWater
    }

    var body: some View {
        ToolScaffold(tool: .pipe, showElevationSheet: $showElevationSheet) {
            @Bindable var settings = settings

            Picker("Solve for", selection: Binding(get: { model.solveFor },
                                                   set: { model.solveFor = $0 })) {
                ForEach(PipeModel.Unknown.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("pipe.solveFor")

            FieldPair {
                NumericField(title: "Flow", spokenTitle: "Water flow", quantity: .waterFlow,
                             system: settings.unitSystem,
                             siValue: Binding(get: { model.flow }, set: { model.flow = $0 }),
                             step: settings.unitSystem == .ip ? 5 : 0.5,
                             isActive: true, identifier: "pipe.flow")
                if model.solveFor == .headLoss {
                    NumericField(title: "Inside diameter", spokenTitle: "Inside diameter",
                                 quantity: .ductSize, system: settings.unitSystem,
                                 siValue: Binding(get: { model.bore }, set: { model.bore = $0 }),
                                 step: settings.unitSystem == .ip ? 0.25 : 5,
                                 isActive: true, identifier: "pipe.bore")
                } else {
                    NumericField(title: "Target head loss", spokenTitle: "Target head loss",
                                 quantity: .waterHeadGradient, system: settings.unitSystem,
                                 siValue: Binding(get: { model.targetGradient },
                                                  set: { model.targetGradient = $0 }),
                                 step: settings.unitSystem == .ip ? 0.5 : 0.1,
                                 isActive: true, identifier: "pipe.target")
                }
            }

            Picker("Pipe material", selection: Binding(get: { model.material },
                                                       set: { model.material = $0 })) {
                ForEach(PipeMaterial.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("pipe.material")

            Picker("Method", selection: Binding(get: { model.method },
                                                set: { model.method = $0 })) {
                ForEach(HeadLossMethod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("pipe.method")

            Toggle("Heating water", isOn: $settings.waterIsHot)
                .font(DS.ui(13))
                .accessibilityIdentifier("pipe.hotWater")
                .accessibilityHint("Hot water erodes copper at a lower velocity, so the ceiling "
                                   + "drops from 8 to 5 feet per second")

            results
        }
    }

    @ViewBuilder
    private var results: some View {
        switch model.solved(water: water, limits: limits) {
        case .success(let solution):
            ResultGrid(tool: .pipe, rows: [
                .init(title: "Inside diameter", value: solution.bore, quantity: .ductSize,
                      emphasised: model.solveFor == .bore),
                .init(title: "Velocity", value: solution.velocity, quantity: .waterVelocity,
                      emphasised: true),
                .init(title: "Head loss", value: solution.gradient,
                      quantity: .waterHeadGradient, emphasised: true),
                .init(title: "By \(plainTitle(model.method.other))", value: solution.otherGradient,
                      quantity: .waterHeadGradient),
            ])

            velocityBanner(solution)
            methodBanner(solution)

        case .failure(let error):
            ErrorBanner(error: error)
        }
    }

    private func plainTitle(_ method: HeadLossMethod) -> String {
        method == .darcyWeisbach ? "Darcy" : "Hazen–Williams"
    }

    private func velocityBanner(_ solution: PipeModel.Solution) -> some View {
        let (kind, title, detail): (StatusBanner.Kind, String, String) = {
            switch solution.status {
            case .tooSlow:
                return (.warning, "Below the usual minimum",
                        "Under \(Fmt.valueWithUnit(si: limits.minimum, .waterVelocity, settings.unitSystem)) "
                        + "the run may not carry air out to the vents.")
            case .inRange:
                return (.ok, "Within the usual window",
                        "\(Fmt.valueWithUnit(si: limits.minimum, .waterVelocity, settings.unitSystem)) "
                        + "to \(Fmt.valueWithUnit(si: limits.maximum, .waterVelocity, settings.unitSystem)).")
            case .tooFast:
                return (.warning, "Above the erosion limit",
                        "The published continuous-service limit for copper is "
                        + "\(Fmt.valueWithUnit(si: limits.maximum, .waterVelocity, settings.unitSystem))"
                        + (settings.waterIsHot ? " for hot water." : " for cold water.")
                        + " Noise now, thinning wall later.")
            }
        }()
        return StatusBanner(kind: kind, title: title, detail: detail)
            .accessibilityIdentifier("pipe.velocityBanner")
    }

    private func methodBanner(_ solution: PipeModel.Solution) -> some View {
        let difference = solution.otherGradient == 0 ? 0
            : abs(solution.gradient - solution.otherGradient) / solution.otherGradient
        return StatusBanner(
            kind: .ok,
            title: "\(plainTitle(model.method)) and \(plainTitle(model.method.other)) differ by "
                 + "\(Fmt.number(difference * 100, decimals: 1)) %",
            detail: "Hazen–Williams is empirical and has no viscosity term, so it cannot see the "
                  + "water temperature. Darcy can. Neither is wrong — but they are not the same "
                  + "number, and a reference book will quote one of them.")
        .accessibilityIdentifier("pipe.methodBanner")
    }
}
