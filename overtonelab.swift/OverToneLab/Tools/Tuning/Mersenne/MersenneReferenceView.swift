import SwiftUI

struct MersenneReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Mersenne's law", "Pitch f = (1/2L)·√(T/μ): tension up → pitch up (√), length up → pitch down, heavier string → pitch down. An octave up needs 4× the tension.")
            card("Fret spacing", "Each fret sits at L·(1 − 2^(−n/12)); the 12th fret halves the string (one octave). Historically the 'rule of 18' (÷17.817).")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: L.loc(t)); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
