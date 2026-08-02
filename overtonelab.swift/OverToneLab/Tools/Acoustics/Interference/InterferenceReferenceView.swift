import SwiftUI

struct InterferenceReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Boundary interference (SBIR)", "A speaker near a wall, floor or desk hears its own reflection delayed by twice the distance, cancelling at (2k−1)·c/(4d). Move the speaker or the boundary to shift the notch out of the way.")
            card("Comb filtering", "Two coherent arrivals a path-length Δ apart comb the spectrum — nulls every c/Δ Hz. The same maths covers a mic + reflection or two overlapping PA sources.")
            card("Depth is ideal", "Notch depth assumes a perfect, full-size reflector. Real, absorptive or small boundaries make shallower notches — treat the frequencies as exact and the depths as worst-case.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: L.loc(t)); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
