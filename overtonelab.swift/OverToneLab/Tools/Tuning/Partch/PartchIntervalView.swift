import SwiftUI

struct PartchIntervalView: View {
    @ObservedObject var vm: PartchTuningViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Interval between two pitches")
                NumberField(title: "Lower pitch", value: $vm.freqLow, unit: "Hz", range: 1...20000)
                NumberField(title: "Upper pitch", value: $vm.freqHigh, unit: "Hz", range: 1...20000)
                ResultRow(label: "Ratio", value: Fmt.f(vm.ratio, 4))
                ResultRow(label: "Interval", value: "\(Fmt.f(vm.cents, 1)) ¢", emphasis: true)
            }.glassCard()
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Nearest just ratio")
                Stepper("Ratio limit  \(vm.limit)", value: $vm.limit, in: 3...31, step: 2)
                ResultRow(label: "Just interval", value: "\(vm.just.num):\(vm.just.den)", emphasis: true)
                ResultRow(label: "Its size", value: "\(Fmt.f(vm.just.cents, 1)) ¢")
                ResultRow(label: "You are off by", value: "\(Fmt.signed(vm.justError, 1)) ¢")
                ResultRow(label: "12-TET", value: "\(vm.nearestSemitone) st  (\(Fmt.signed(vm.etDeviation, 1)) ¢)")
            }.glassCard()
        }
    }
}
