import SwiftUI

struct FormantReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Formants", "The vocal tract's resonances shape a sound into a vowel. F1 and F2 (the lowest two) do most of the identifying.")
            card("Quarter-wave tube", "A uniform tract closed at the glottis and open at the lips resonates at (2n−1)·c/(4L) — the odd-harmonic series, giving 500/1500/2500 Hz for a neutral 17.5 cm tract.")
            card("Length & scale", "Shorter tracts (children, higher voices) raise every formant proportionally: F ∝ 1/L.")
            card("Estimate", "A uniform-tube idealization — real tracts vary in cross-section. Use the vowel table for realistic targets.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: L.loc(t)); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
