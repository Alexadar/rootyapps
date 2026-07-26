import SwiftUI

struct BeatsView: View {
    @ObservedObject var vm: PitchViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Beat frequency")
                NumberField(title: "Tone A", value: $vm.f1, unit: "Hz", range: 1...20000)
                NumberField(title: "Tone B", value: $vm.f2, unit: "Hz", range: 1...20000)
                ResultRow(label: "Beat rate", value: "\(Fmt.f(vm.beatHz, 2)) Hz", emphasis: true)
                ResultRow(label: "Interval", value: "\(Fmt.signed(vm.beatCents, 1)) ¢")
                Text("Two close tones beat at their difference — tune by slowing the beats to zero.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
