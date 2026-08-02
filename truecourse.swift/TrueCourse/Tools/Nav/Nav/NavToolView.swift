import SwiftUI
import NavKit

@MainActor
final class NavViewModel: ObservableObject {
    // Time-speed-distance (solve for the missing one)
    @Published var distanceNm = 150.0
    @Published var gsKt = 120.0
    @Published var timeMin = 75.0

    var solvedTimeMin: Double { Nav.timeMin(distanceNm: distanceNm, gsKt: gsKt) }
    var solvedDistanceNm: Double { Nav.distanceNm(gsKt: gsKt, timeMin: timeMin) }
    var solvedGsKt: Double { Nav.groundspeedKt(distanceNm: distanceNm, timeMin: timeMin) }
}

struct NavToolView: View {
    @Environment(\.tc) private var tc
    @StateObject private var vm = NavViewModel()
    @State private var screen = initialScreen()

    var body: some View {
        VStack(spacing: 16) {
            SubScreenPicker(titles: ["Time", "Distance", "Speed"], selection: $screen)
            switch screen {
            case 1: distance
            case 2: speed
            default: time
            }
        }
    }

    private var time: some View {
        AdaptiveStack(spacing: 16) {
            inputs(distance: true, speed: true, time: false)
            ResultCard(accent: tc.accent(.planning)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Leg time")
                    ResultRow(label: "Time enroute", value: Fmt.minutesSeconds(vm.solvedTimeMin), emphasis: true)
                    ResultRow(label: "Minutes", value: Fmt.f(vm.solvedTimeMin, 1), unit: "min")
                }
            }
        }
    }

    private var distance: some View {
        AdaptiveStack(spacing: 16) {
            inputs(distance: false, speed: true, time: true)
            ResultCard(accent: tc.accent(.planning)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Distance")
                    ResultRow(label: "Distance flown", value: Fmt.i(vm.solvedDistanceNm), unit: "nm", emphasis: true)
                }
            }
        }
    }

    private var speed: some View {
        AdaptiveStack(spacing: 16) {
            inputs(distance: true, speed: false, time: true)
            ResultCard(accent: tc.accent(.planning)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Groundspeed")
                    ResultRow(label: "Groundspeed", value: Fmt.i(vm.solvedGsKt), unit: "kt", emphasis: true)
                }
            }
        }
    }

    @ViewBuilder private func inputs(distance: Bool, speed: Bool, time: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Inputs")
            if distance { NumberField(title: "Distance", value: $vm.distanceNm, unit: "nm", range: Bounds.distanceNm) }
            if speed { NumberField(title: "Groundspeed", value: $vm.gsKt, unit: "kt", range: Bounds.groundspeedKt) }
            if time { NumberField(title: "Time", value: $vm.timeMin, unit: "min", range: Bounds.timeMin) }
        }
        .instrumentCard()
        .inputColumn()
    }
}
