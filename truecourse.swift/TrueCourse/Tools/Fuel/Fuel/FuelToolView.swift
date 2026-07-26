import SwiftUI
import FuelKit

@MainActor
final class FuelViewModel: ObservableObject {
    @Published var gph = 10.0
    @Published var timeHr = 2.5
    @Published var fuelGal = 40.0
    @Published var gsKt = 120.0

    var requiredGal: Double { Fuel.requiredGal(gph: gph, timeHr: timeHr) }
    var requiredLb: Double { requiredGal * Fuel.avgasLbPerGal }
    var enduranceHr: Double { Fuel.enduranceHr(fuelGal: fuelGal, gph: gph) }
    var specificRange: Double { Fuel.specificRangeNmPerGal(gsKt: gsKt, gph: gph) }
    var rangeNm: Double { specificRange * fuelGal }
}

struct FuelToolView: View {
    @Environment(\.tc) private var tc
    @StateObject private var vm = FuelViewModel()
    @State private var screen = initialScreen()

    var body: some View {
        VStack(spacing: 16) {
            SubScreenPicker(titles: ["Required", "Endurance", "Range"], selection: $screen)
            switch screen {
            case 1: endurance
            case 2: range
            default: required
            }
        }
    }

    private var required: some View {
        AdaptiveStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Inputs")
                NumberField(title: "Burn rate", value: $vm.gph, unit: "gph", range: Bounds.fuelGph)
                NumberField(title: "Time", value: $vm.timeHr, unit: "h", range: Bounds.timeHr)
            }
            .instrumentCard()
            .inputColumn()
            ResultCard(accent: tc.accent(.planning)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Fuel required")
                    ResultRow(label: "Fuel burned", value: Fmt.f(vm.requiredGal, 1), unit: "gal", emphasis: true)
                    ResultRow(label: "Weight (avgas)", value: Fmt.i(vm.requiredLb), unit: "lb")
                }
            }
        }
    }

    private var endurance: some View {
        AdaptiveStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Inputs")
                NumberField(title: "Fuel aboard", value: $vm.fuelGal, unit: "gal", range: Bounds.fuelGal)
                NumberField(title: "Burn rate", value: $vm.gph, unit: "gph", range: Bounds.fuelGph)
            }
            .instrumentCard()
            .inputColumn()
            ResultCard(accent: tc.accent(.planning)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Endurance")
                    ResultRow(label: "Endurance", value: Fmt.hoursMinutes(vm.enduranceHr), emphasis: true)
                    ResultRow(label: "Decimal hours", value: Fmt.f(vm.enduranceHr, 2), unit: "h")
                }
            }
        }
    }

    private var range: some View {
        AdaptiveStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Inputs")
                NumberField(title: "Groundspeed", value: $vm.gsKt, unit: "kt", range: Bounds.groundspeedKt)
                NumberField(title: "Burn rate", value: $vm.gph, unit: "gph", range: Bounds.fuelGph)
                NumberField(title: "Fuel aboard", value: $vm.fuelGal, unit: "gal", range: Bounds.fuelGal)
            }
            .instrumentCard()
            .inputColumn()
            ResultCard(accent: tc.accent(.planning)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Range")
                    ResultRow(label: "Specific range", value: Fmt.f(vm.specificRange, 1), unit: "nm/gal", emphasis: true)
                    ResultRow(label: "Still-air range", value: Fmt.i(vm.rangeNm), unit: "nm")
                }
            }
        }
    }
}
