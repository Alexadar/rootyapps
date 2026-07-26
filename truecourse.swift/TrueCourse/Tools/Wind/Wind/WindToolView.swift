import SwiftUI
import WindKit

@MainActor
final class WindViewModel: ObservableObject {
    // Solve
    @Published var courseDeg = 90.0
    @Published var tasKt = 120.0
    @Published var windDirDeg = 180.0
    @Published var windSpeedKt = 30.0
    // Components
    @Published var runwayHeadingDeg = 90.0
    // Derive
    @Published var dCourseDeg = 90.0
    @Published var dHeadingDeg = 104.5
    @Published var dTasKt = 120.0
    @Published var dGsKt = 116.2

    private var demoTimer: Timer?
    private var demoTick = 0

    /// Reel demo: a SINGLE, slow, contiguous change. Only the wind **direction** sweeps —
    /// wind speed is held constant — so the vectors rotate and heading/GS/WCA all travel from
    /// one clear cause (not two values moving at once). Played at 2× the standard leg time so
    /// the digits roll slowly enough to read on camera.
    private static let demoWindSpeedKt = 40.0                       // held constant; only dir moves
    private static let demoTicksPerLeg = DemoSweep.ticksPerLeg * 2  // 2× slower than other scenes
    private static let demoWarmup = 14                              // ~0.8 s settle, then the sweep
    private static let demoKeyframes: [Double] = [
        180,   // crosswind from the south
        240,   // → quartering tailwind (only the direction rotates)
    ]

    init() {
        guard DemoSweep.isOn else { return }
        windSpeedKt = Self.demoWindSpeedKt          // demo-only: constant while direction sweeps
        demoTimer = Timer.scheduledTimer(withTimeInterval: DemoSweep.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.demoTick += 1
                guard let p = DemoSweep.phase(tick: self.demoTick, legs: Self.demoKeyframes.count,
                                              warmup: Self.demoWarmup,
                                              ticksPerLeg: Self.demoTicksPerLeg) else { return }
                let from = Self.demoKeyframes[p.leg]
                let to = Self.demoKeyframes[(p.leg + 1) % Self.demoKeyframes.count]
                self.windDirDeg = (from + (to - from) * p.ease).rounded()
            }
        }
    }

    var solution: (headingDeg: Double, gsKt: Double, wcaDeg: Double)? {
        Wind.solution(courseDeg: courseDeg, tasKt: tasKt, windDirDeg: windDirDeg, windSpeedKt: windSpeedKt)
    }
    var components: (headwindKt: Double, crosswindKt: Double) {
        Wind.components(runwayHeadingDeg: runwayHeadingDeg, windDirDeg: windDirDeg, windSpeedKt: windSpeedKt)
    }
    var derived: (windDirDeg: Double, windSpeedKt: Double) {
        Wind.derive(courseDeg: dCourseDeg, headingDeg: dHeadingDeg, tasKt: dTasKt, gsKt: dGsKt)
    }
}

struct WindToolView: View {
    @Environment(\.tc) private var tc
    @StateObject private var vm = WindViewModel()
    @State private var screen = initialScreen()

    var body: some View {
        VStack(spacing: 16) {
            SubScreenPicker(titles: ["Solve", "Components", "Derive"], selection: $screen)
            switch screen {
            case 1: components
            case 2: derive
            default: solve
            }
        }
    }

    private var solve: some View {
        AdaptiveStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Course & wind")
                NumberField(title: "Course", value: $vm.courseDeg, unit: "°T", range: Bounds.bearingDeg)
                NumberField(title: "True airspeed", value: $vm.tasKt, unit: "kt", range: Bounds.airspeedKt)
                NumberField(title: "Wind from", value: $vm.windDirDeg, unit: "°T", range: Bounds.bearingDeg)
                NumberField(title: "Wind speed", value: $vm.windSpeedKt, unit: "kt", range: Bounds.windSpeedKt)
            }
            .instrumentCard()
            .inputColumn()

            ResultCard(accent: tc.accent(.planning)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Solution")
                    if let s = vm.solution {
                        ResultRow(label: "Heading", value: Fmt.heading(s.headingDeg), emphasis: true)
                        ResultRow(label: "Groundspeed", value: Fmt.i(s.gsKt), unit: "kt")
                        ResultRow(label: "Wind correction", value: Fmt.signed(s.wcaDeg, 0), unit: "°")
                        WindTriangleView(solution: WindSolution(
                            trueCourse: vm.courseDeg, trueHeading: s.headingDeg,
                            tas: vm.tasKt, groundSpeed: s.gsKt,
                            windFrom: vm.windDirDeg, windSpeed: vm.windSpeedKt, wca: s.wcaDeg))
                            .frame(height: 230)
                            .padding(.top, 4)
                    } else {
                        Label("Crosswind exceeds TAS — course cannot be held.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(tc.warning)
                    }
                }
            }
        }
    }

    private var components: some View {
        AdaptiveStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Runway & wind")
                NumberField(title: "Runway heading", value: $vm.runwayHeadingDeg, unit: "°T", range: Bounds.bearingDeg)
                NumberField(title: "Wind from", value: $vm.windDirDeg, unit: "°T", range: Bounds.bearingDeg)
                NumberField(title: "Wind speed", value: $vm.windSpeedKt, unit: "kt", range: Bounds.windSpeedKt)
            }
            .instrumentCard()
            .inputColumn()

            ResultCard(accent: tc.accent(.planning)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Components")
                    let c = vm.components
                    ResultRow(label: c.crosswindKt >= 0 ? "Crosswind (from right)" : "Crosswind (from left)",
                              value: Fmt.i(abs(c.crosswindKt)), unit: "kt", emphasis: true)
                    ResultRow(label: c.headwindKt >= 0 ? "Headwind" : "Tailwind",
                              value: Fmt.i(abs(c.headwindKt)), unit: "kt")
                }
            }
        }
    }

    private var derive: some View {
        AdaptiveStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Measured flight")
                NumberField(title: "Course (track)", value: $vm.dCourseDeg, unit: "°T", range: Bounds.bearingDeg)
                NumberField(title: "Heading flown", value: $vm.dHeadingDeg, unit: "°T", range: Bounds.bearingDeg)
                NumberField(title: "True airspeed", value: $vm.dTasKt, unit: "kt", range: Bounds.airspeedKt)
                NumberField(title: "Groundspeed", value: $vm.dGsKt, unit: "kt", range: Bounds.groundspeedKt)
            }
            .instrumentCard()
            .inputColumn()

            ResultCard(accent: tc.accent(.planning)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Derived wind")
                    let w = vm.derived
                    ResultRow(label: "Wind from", value: Fmt.heading(w.windDirDeg), emphasis: true)
                    ResultRow(label: "Wind speed", value: Fmt.i(w.windSpeedKt), unit: "kt")
                }
            }
        }
    }
}
