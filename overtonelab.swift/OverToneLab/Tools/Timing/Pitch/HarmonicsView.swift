import SwiftUI

struct HarmonicsView: View {
    @ObservedObject var vm: PitchViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Harmonic series")
                NumberField(title: "Fundamental", value: $vm.fundamental, unit: "Hz", range: 1...20000)
            }.glassCard()
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Partials", trailing: "cents vs 12-TET")
                ForEach(vm.harmonics, id: \.n) { h in
                    HStack {
                        Text("#\(h.n)").foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                        Text("\(Fmt.f(h.hz, 1)) Hz").monospacedDigit()
                        Spacer()
                        Text("\(Fmt.signed(h.cents, 0)) ¢").foregroundStyle(.tint).monospacedDigit()
                    }.font(.callout)
                }
                Text("The 7th and 11th partials sit far from any tempered key — the roots of blue notes.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
