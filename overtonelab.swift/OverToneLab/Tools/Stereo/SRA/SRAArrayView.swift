import SwiftUI
import StereoKit

struct SRAArrayView: View {
    @ObservedObject var vm: SRAViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Array")
                Picker("Pattern", selection: $vm.pattern) {
                    ForEach(Stereo.Pattern.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                NumberField(title: "Mic angle", value: $vm.micAngle, unit: "°", range: 0...180)
                NumberField(title: "Capsule spacing", value: $vm.spacing, unit: "cm", range: 0...50)
                NumberField(title: "Speed of sound", value: $vm.speed, unit: "m/s", range: 330...350)
                ResultRow(label: "Recording angle", value: "\(Fmt.f(vm.sra, 0))°", emphasis: true)
                ResultRow(label: "Half angle", value: "±\(Fmt.f(vm.sra / 2, 0))°")
                ResultRow(label: "Nearest technique", value: vm.nearest.name)
            }.glassCard()

            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "At source angle")
                NumberField(title: "Source angle", value: $vm.probe, unit: "°", range: 0...90)
                ResultRow(label: "Level difference", value: "\(Fmt.f(vm.levelDiff, 2)) dB")
                ResultRow(label: "Time difference", value: "\(Fmt.f(vm.timeDiff, 0)) µs")
            }.glassCard()
        }
    }
}
