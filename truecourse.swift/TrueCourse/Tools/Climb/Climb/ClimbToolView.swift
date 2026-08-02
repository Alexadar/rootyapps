import SwiftUI
import ClimbDescentKit

@MainActor
final class ClimbViewModel: ObservableObject {
    // Descent
    @Published var altitudeToLoseFt = 3000.0
    @Published var distanceNm = 10.0
    @Published var gsKt = 120.0
    @Published var todGradientFtPerNm = 318.0
    // Gradient
    @Published var gradientFtPerNm = 300.0
    @Published var gradientGsKt = 90.0
    // Glide
    @Published var glideRatio = 9.0
    @Published var heightFt = 5000.0

    var descentRateFpm: Double { ClimbDescent.descentRateFpm(altitudeToLoseFt: altitudeToLoseFt, distanceNm: distanceNm, gsKt: gsKt) }
    var topOfDescentNm: Double { ClimbDescent.topOfDescentNm(altitudeToLoseFt: altitudeToLoseFt, gradientFtPerNm: todGradientFtPerNm) }
    var gradientPercent: Double { ClimbDescent.gradientPercent(ftPerNm: gradientFtPerNm) }
    var gradientDegrees: Double { ClimbDescent.gradientDegrees(ftPerNm: gradientFtPerNm) }
    var requiredRateFpm: Double { ClimbDescent.rateFpm(gradientFtPerNm: gradientFtPerNm, gsKt: gradientGsKt) }
    var glideDistanceNm: Double { ClimbDescent.glideDistanceNm(glideRatio: glideRatio, heightFt: heightFt) }
}

struct ClimbToolView: View {
    @Environment(\.tc) private var tc
    @StateObject private var vm = ClimbViewModel()
    @State private var screen = initialScreen()

    var body: some View {
        VStack(spacing: 16) {
            SubScreenPicker(titles: ["Descent", "Gradient", "Glide"], selection: $screen)
            switch screen {
            case 1: gradient
            case 2: glide
            default: descent
            }
        }
    }

    private var descent: some View {
        AdaptiveStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Descent planning")
                NumberField(title: "Altitude to lose", value: $vm.altitudeToLoseFt, unit: "ft", range: Bounds.heightFt)
                NumberField(title: "Distance", value: $vm.distanceNm, unit: "nm", range: Bounds.distanceNm)
                NumberField(title: "Groundspeed", value: $vm.gsKt, unit: "kt", range: Bounds.groundspeedKt)
            }
            .instrumentCard()
            .inputColumn()
            ResultCard(accent: tc.accent(.planning)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Rate & top of descent")
                    ResultRow(label: "Descent rate", value: Fmt.i(vm.descentRateFpm), unit: "fpm", emphasis: true)
                    NumberField(title: "Descent gradient", value: $vm.todGradientFtPerNm, unit: "ft/nm", range: Bounds.climbGradientFtPerNm)
                    ResultRow(label: "Begin descent", value: Fmt.f(vm.topOfDescentNm, 1), unit: "nm out")
                }
            }
        }
    }

    private var gradient: some View {
        AdaptiveStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Climb gradient")
                NumberField(title: "Gradient", value: $vm.gradientFtPerNm, unit: "ft/nm", range: Bounds.climbGradientFtPerNm)
                NumberField(title: "Groundspeed", value: $vm.gradientGsKt, unit: "kt", range: Bounds.groundspeedKt)
            }
            .instrumentCard()
            .inputColumn()
            ResultCard(accent: tc.accent(.planning)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Result")
                    ResultRow(label: "Required climb rate", value: Fmt.i(vm.requiredRateFpm), unit: "fpm", emphasis: true)
                    ResultRow(label: "Gradient", value: Fmt.f(vm.gradientPercent, 2), unit: "%")
                    ResultRow(label: "Angle", value: Fmt.f(vm.gradientDegrees, 2), unit: "°")
                }
            }
        }
    }

    private var glide: some View {
        AdaptiveStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Glide")
                NumberField(title: "Glide ratio (:1)", value: $vm.glideRatio, unit: ":1", range: Bounds.glideRatio)
                NumberField(title: "Height AGL", value: $vm.heightFt, unit: "ft", range: Bounds.heightFt)
            }
            .instrumentCard()
            .inputColumn()
            ResultCard(accent: tc.accent(.planning)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Result")
                    ResultRow(label: "Glide distance", value: Fmt.f(vm.glideDistanceNm, 1), unit: "nm", emphasis: true)
                }
            }
        }
    }
}
