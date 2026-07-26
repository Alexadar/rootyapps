import SwiftUI
import AirspeedKit

@MainActor
final class AirspeedViewModel: ObservableObject {
    @Published var casKt = 100.0
    @Published var pressureAltFt = 10000.0
    @Published var oatC = -5.0
    // Mach
    @Published var machTasKt = 480.0
    @Published var machOatC = -56.5

    var tasKt: Double { Airspeed.tas(casKt: casKt, pressureAltFt: pressureAltFt, oatC: oatC) }
    var mach: Double { Airspeed.mach(tasKt: machTasKt, oatC: machOatC) }
    var speedOfSoundKt: Double { Airspeed.speedOfSoundKt(oatC: machOatC) }
}

struct AirspeedToolView: View {
    @Environment(\.tc) private var tc
    @StateObject private var vm = AirspeedViewModel()
    @State private var screen = initialScreen()

    var body: some View {
        VStack(spacing: 16) {
            SubScreenPicker(titles: ["TAS", "Mach"], selection: $screen)
            if screen == 1 { mach } else { tas }
        }
    }

    private var tas: some View {
        AdaptiveStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Inputs")
                NumberField(title: "Calibrated airspeed", value: $vm.casKt, unit: "kt", range: Bounds.airspeedKt)
                NumberField(title: "Pressure altitude", value: $vm.pressureAltFt, unit: "ft", range: Bounds.altitudeFt)
                NumberField(title: "Outside air temp", value: $vm.oatC, unit: "°C", range: Bounds.temperatureC, allowsNegative: true)
            }
            .instrumentCard()
            .inputColumn()
            ResultCard(accent: tc.accent(.performance)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Result")
                    ResultRow(label: "True airspeed", value: Fmt.i(vm.tasKt), unit: "kt", emphasis: true)
                    Text("TAS = CAS ÷ √σ, with the ISA density ratio σ from pressure altitude and temperature.")
                        .font(.caption).foregroundStyle(tc.textSecondary)
                }
            }
        }
    }

    private var mach: some View {
        AdaptiveStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Inputs")
                NumberField(title: "True airspeed", value: $vm.machTasKt, unit: "kt", range: Bounds.airspeedKt)
                NumberField(title: "Outside air temp", value: $vm.machOatC, unit: "°C", range: Bounds.temperatureC, allowsNegative: true)
            }
            .instrumentCard()
            .inputColumn()
            ResultCard(accent: tc.accent(.performance)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Result")
                    ResultRow(label: "Mach number", value: Fmt.f(vm.mach, 3), emphasis: true)
                    ResultRow(label: "Speed of sound", value: Fmt.i(vm.speedOfSoundKt), unit: "kt")
                }
            }
        }
    }
}
