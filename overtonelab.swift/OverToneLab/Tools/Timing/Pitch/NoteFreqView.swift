import SwiftUI

struct NoteFreqView: View {
    @ObservedObject var vm: PitchViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Note → frequency")
                Stepper("MIDI \(vm.midi)  ·  \(vm.noteName)", value: $vm.midi, in: 0...127)
                ResultRow(label: "Frequency", value: "\(Fmt.f(vm.noteHz, 2)) Hz", emphasis: true, id: "result.pitch")
                ResultRow(label: "Wavelength", value: "\(Fmt.f(vm.wavelengthM, 3)) m")
            }.glassCard()
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Frequency → note")
                NumberField(title: "Frequency", value: $vm.freqInput, unit: "Hz", range: 1...30_000)
                ResultRow(label: "Nearest note", value: vm.nearestNote, emphasis: true)
                ResultRow(label: "Deviation", value: "\(Fmt.signed(vm.centsOff, 1)) ¢")
                Text("12-TET, A4 = 440 Hz (ISO 16).")
                    .font(.caption).foregroundStyle(.secondary)
            }.glassCard()
        }
    }
}
