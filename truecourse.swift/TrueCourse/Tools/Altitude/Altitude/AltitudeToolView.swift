import SwiftUI
import AltitudeKit

@MainActor
final class AltitudeViewModel: ObservableObject {
    // Density
    @Published var pressureAltFt = 5000.0
    @Published var oatC = 30.0
    // Pressure
    @Published var indicatedAltFt = 5000.0
    @Published var altimeterInHg = 29.92
    // Flight environment
    @Published var tempC = 25.0
    @Published var dewpointC = 15.0
    @Published var surfaceTempC = 15.0
    @Published var elevationFt = 0.0
    @Published var gsKt = 100.0

    private var demoTimer: Timer?
    private var demoTick = 0

    /// Reel demo: sweep OAT 0…40 °C — at PA 5,000 the density altitude rolls ≈ 4,380 → 8,850 ft.
    init() {
        guard DemoSweep.isOn else { return }
        demoTimer = Timer.scheduledTimer(withTimeInterval: DemoSweep.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.demoTick += 1
                if let t = DemoSweep.value(tick: self.demoTick, a: 0, b: 40) { self.oatC = t }
            }
        }
    }

    var densityAltFt: Double { Altitude.densityAltitudeFt(pressureAltFt: pressureAltFt, oatC: oatC) }
    var isaDevC: Double { oatC - Altitude.isaTempC(altitudeFt: pressureAltFt) }
    var pressureAltFromSetting: Double { Altitude.pressureAltitudeFt(indicatedAltFt: indicatedAltFt, altimeterInHg: altimeterInHg) }
    var cloudBaseFt: Double { Altitude.cloudBaseFt(tempC: tempC, dewpointC: dewpointC) }
    var freezingLevelFt: Double { Altitude.freezingLevelFt(surfaceTempC: surfaceTempC, elevationFt: elevationFt) }
    var pivotalAltFt: Double { Altitude.pivotalAltitudeFt(gsKt: gsKt) }
}

struct AltitudeToolView: View {
    @Environment(\.tc) private var tc
    @StateObject private var vm = AltitudeViewModel()
    @State private var screen = initialScreen()

    var body: some View {
        VStack(spacing: 16) {
            SubScreenPicker(titles: ["Density", "Pressure", "Flight env"], selection: $screen)
            switch screen {
            case 1: pressure
            case 2: flightEnv
            default: density
            }
        }
    }

    private var density: some View {
        AdaptiveStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Inputs")
                NumberField(title: "Pressure altitude", value: $vm.pressureAltFt, unit: "ft", range: Bounds.altitudeFt)
                NumberField(title: "Outside air temp", value: $vm.oatC, unit: "°C", range: Bounds.temperatureC, allowsNegative: true)
            }
            .instrumentCard()
            .inputColumn()
            ResultCard(accent: tc.accent(.performance)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Result")
                    ResultRow(label: "Density altitude", value: Fmt.i(vm.densityAltFt), unit: "ft", emphasis: true)
                    ResultRow(label: "ISA deviation", value: Fmt.signed(vm.isaDevC, 0), unit: "°C")
                }
            }
        }
    }

    private var pressure: some View {
        AdaptiveStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Inputs")
                NumberField(title: "Indicated altitude", value: $vm.indicatedAltFt, unit: "ft", range: Bounds.altitudeFt)
                NumberField(title: "Altimeter setting", value: $vm.altimeterInHg, unit: "inHg", range: Bounds.altimeterInHg)
            }
            .instrumentCard()
            .inputColumn()
            ResultCard(accent: tc.accent(.performance)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Result")
                    ResultRow(label: "Pressure altitude", value: Fmt.i(vm.pressureAltFromSetting), unit: "ft", emphasis: true)
                    Text("≈ 1,000 ft per inHg away from the standard 29.92.")
                        .font(.caption).foregroundStyle(tc.textSecondary)
                }
            }
        }
    }

    private var flightEnv: some View {
        AdaptiveStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Cloud base & freezing")
                NumberField(title: "Temperature", value: $vm.tempC, unit: "°C", range: Bounds.temperatureC, allowsNegative: true)
                NumberField(title: "Dew point", value: $vm.dewpointC, unit: "°C", range: Bounds.temperatureC, allowsNegative: true)
                ResultRow(label: "Convective cloud base", value: Fmt.i(vm.cloudBaseFt), unit: "ft AGL", emphasis: true)
                Divider().overlay(tc.hairline)
                NumberField(title: "Surface temp", value: $vm.surfaceTempC, unit: "°C", range: Bounds.temperatureC, allowsNegative: true)
                NumberField(title: "Field elevation", value: $vm.elevationFt, unit: "ft", range: Bounds.elevationFt, allowsNegative: true)
                ResultRow(label: "Freezing level", value: Fmt.i(vm.freezingLevelFt), unit: "ft MSL")
            }
            .instrumentCard()
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Pivotal altitude")
                NumberField(title: "Groundspeed", value: $vm.gsKt, unit: "kt", range: Bounds.groundspeedKt)
                ResultRow(label: "Pivotal altitude", value: Fmt.i(vm.pivotalAltFt), unit: "ft AGL")
            }
            .instrumentCard()
        }
    }
}
