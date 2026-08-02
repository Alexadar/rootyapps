import SwiftUI

struct DistanceDelayView: View {
    @ObservedObject var vm: DelayViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Distance delay")
                NumberField(title: "Distance", value: $vm.meters, unit: "m", range: 0...100_000)
                ResultRow(label: "Propagation delay", value: "\(Fmt.f(vm.distanceMs, 2)) ms", emphasis: true)
                Text(vm.withinHaas
                     ? "Within the Haas window (≤35 ms) — perceived as one fused source."
                     : "Beyond ~35 ms — heard as a distinct echo.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Sound travels 343 m/s. Use this to time-align a delayed speaker to a distant one.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
