import SwiftUI

struct EndView: View {
    @ObservedObject var vm: PipeViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "End correction")
                NumberField(title: "Bore radius", value: $vm.radiusMm, unit: "mm", range: 0.1...500)
                ResultRow(label: "Flanged end", value: "\(Fmt.f(vm.endFlangedMm, 2)) mm", emphasis: true)
                ResultRow(label: "Unflanged end", value: "\(Fmt.f(vm.endUnflangedMm, 2)) mm", emphasis: true)
                Text("Add to the physical length for the effective acoustic length at each open end.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
