import SwiftUI

struct VowelsView: View {
    @ObservedObject var vm: FormantViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Vowel formants")
                Picker("Vowel", selection: $vm.selectedVowel) {
                    ForEach(vm.vowels) { Text("[\($0.ipa)] \($0.keyword)").tag($0.ipa) }
                }
                ResultRow(label: "F1", value: "\(Fmt.f(vm.vowel.f1, 0)) Hz", emphasis: true)
                ResultRow(label: "F2", value: "\(Fmt.f(vm.vowel.f2, 0)) Hz", emphasis: true)
                Text("Mean adult-male values, Peterson & Barney (1952). Dial a formant filter or synth to these to voice a vowel.")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
