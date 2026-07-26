import SwiftUI

struct PartchReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Cents", "1200·log₂(ratio). An octave is 1200 ¢, an equal semitone 100 ¢. The unit for comparing any two tunings.")
            card("Just intonation", "Small whole-number ratios (3:2 fifth, 5:4 major third, 7:4 harmonic seventh). The ratio limit bounds how complex a fraction the search will consider.")
            card("Tenney height", "log₂(n·d) — a consonance proxy. 3:2 (2.58) is far simpler than 15:8 (6.91).")
            card("Just vs 12-TET", "Equal temperament splits the octave into 12 equal 100 ¢ steps, so most just intervals land a few cents off. This shows both.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: L.loc(t)); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
