import SwiftUI
import WeightBalanceKit

@MainActor
final class WeightBalanceViewModel: ObservableObject {
    // A representative light-single loading sheet (editable weights, fixed arms).
    @Published var stations: [Station] = [
        Station(id: 0, name: "Empty aircraft", weightLb: 1000, armIn: 36),
        Station(id: 1, name: "Front seats",    weightLb: 340,  armIn: 37),
        Station(id: 2, name: "Fuel",           weightLb: 180,  armIn: 48),
        Station(id: 3, name: "Baggage",        weightLb: 20,   armIn: 95),
    ]

    // Representative CG envelope (CG in, weight lb).
    let envelope = [
        EnvelopePoint(cgIn: 35.0, weightLb: 1500),
        EnvelopePoint(cgIn: 41.0, weightLb: 2550),
        EnvelopePoint(cgIn: 47.3, weightLb: 2550),
        EnvelopePoint(cgIn: 47.3, weightLb: 1500),
    ]

    private var demoTimer: Timer?
    private var demoTick = 0

    /// Reel demo: load/unload baggage so the CG point visibly travels across the envelope and
    /// the verdict flips WITHIN LIMITS → OUT OF LIMITS. Held still during a warm-up so the reel
    /// can open the Envelope screen first, then the motion starts.
    init() {
        guard DemoSweep.isOn else { return }
        demoTimer = Timer.scheduledTimer(withTimeInterval: DemoSweep.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.demoTick += 1
                if let w = DemoSweep.value(tick: self.demoTick, a: 20, b: 340) {
                    self.stations[3].weightLb = w           // baggage: CG travels the envelope
                }
            }
        }
    }

    var result: (totalWeightLb: Double, totalMomentLbIn: Double, cgIn: Double) {
        WeightBalance.cg(stations: stations)
    }
    var inside: Bool {
        WeightBalance.withinEnvelope(cgIn: result.cgIn, weightLb: result.totalWeightLb, envelope: envelope)
    }

    /// Zero-fuel (landing) loading — the CG travels as fuel burns off.
    var landing: (totalWeightLb: Double, totalMomentLbIn: Double, cgIn: Double) {
        let burned = stations.map { st -> Station in
            st.name.localizedCaseInsensitiveContains("fuel")
                ? Station(id: st.id, name: st.name, weightLb: 0, armIn: st.armIn) : st
        }
        return WeightBalance.cg(stations: burned)
    }
}

struct WeightBalanceToolView: View {
    @Environment(\.tc) private var tc
    @StateObject private var vm = WeightBalanceViewModel()
    @State private var screen = initialScreen()

    var body: some View {
        VStack(spacing: 16) {
            SubScreenPicker(titles: ["Loading", "Envelope"], selection: $screen)
            if screen == 1 { envelopeScreen } else { loading }
        }
    }

    private var loading: some View {
        AdaptiveStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Loading stations", trailing: "arm (in)")
                ForEach($vm.stations) { $st in
                    HStack {
                        Text(st.name).font(.callout).foregroundStyle(tc.textPrimary)
                        Spacer()
                        TextField("lb", value: $st.weightLb, format: .number)
                            .accessibilityIdentifier("station.\(st.name)")
                            .multilineTextAlignment(.trailing)
                            .font(.system(.callout, design: .monospaced).weight(.semibold))
                            .frame(minWidth: 60)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(tc.chipFill, in: .rect(cornerRadius: TC.rChip))
                            #if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
                            #endif
                            .textFieldStyle(.plain)
                        Text("@ \(Fmt.i(st.armIn))\"").font(.caption).foregroundStyle(tc.textTertiary)
                            .frame(width: 60, alignment: .leading)
                    }
                }
            }
            .instrumentCard()
            .inputColumn()
            ResultCard(accent: tc.accent(.performance)) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Result", trailing: vm.inside ? "IN ENVELOPE" : "OUT",
                               trailingID: "verdict.loading")
                    ResultRow(label: "Centre of gravity", value: Fmt.f(vm.result.cgIn, 1), unit: "in", emphasis: true)
                    ResultRow(label: "Gross weight", value: Fmt.i(vm.result.totalWeightLb), unit: "lb")
                    ResultRow(label: "Total moment", value: Fmt.i(vm.result.totalMomentLbIn), unit: "lb·in")
                }
            }
        }
    }

    // Single full-width chart card — the envelope is the hero on its own.
    private var envelopeScreen: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "CG envelope",
                       trailing: vm.inside ? "WITHIN LIMITS" : "OUT OF LIMITS",
                       trailingID: "verdict.envelope")
            CGEnvelopeChart(
                envelopes: [CGEnvelope(name: "Normal",
                                       vertices: vm.envelope.map { (arm: $0.cgIn, weight: $0.weightLb) })],
                takeoff: CGPointSample(label: "Takeoff", arm: vm.result.cgIn, weight: vm.result.totalWeightLb),
                landing: CGPointSample(label: "Landing", arm: vm.landing.cgIn, weight: vm.landing.totalWeightLb),
                armDomain: 33...49,
                weightDomain: 1400...2650,
                isWithin: vm.inside)
            Text(vm.inside
                 ? "Loaded point is inside the certificated envelope."
                 : "Loaded point is OUTSIDE the envelope — do not fly as loaded.")
                .font(.caption)
                .foregroundStyle(vm.inside ? tc.textSecondary : tc.warning)
        }
        .instrumentCard()
    }
}
