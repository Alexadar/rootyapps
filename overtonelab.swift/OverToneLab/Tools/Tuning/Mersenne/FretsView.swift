import SwiftUI

struct FretsView: View {
    @ObservedObject var vm: StringsViewModel
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Fretboard (equal temperament)")
                NumberField(title: "Scale length", value: $vm.scaleIn, unit: "in", range: 1...100)
                NumberField(title: "Frets", value: $vm.frets, range: 1...48)
            }.glassCard()
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Distance from nut")
                ForEach(vm.fretPositions, id: \.fret) { p in
                    HStack {
                        Text("Fret \(p.fret)").foregroundStyle(.secondary).frame(width: 66, alignment: .leading)
                        Spacer()
                        Text("\(Fmt.f(p.distance, 4)) in").monospacedDigit()
                    }.font(.callout)
                    if p.fret < vm.fretPositions.count { Divider().overlay(.white.opacity(0.06)) }
                }
            }.glassCard()
        }
    }
}
