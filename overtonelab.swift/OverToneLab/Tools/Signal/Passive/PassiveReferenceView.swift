import SwiftUI

struct PassiveReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Passive filters", "Real R, L and C parts set an actual corner or resonance — the counterpart to Butterworth's idealized response.")
            card("Formulas", "RC: f = 1/(2πRC). RL: f = R/(2πL). LC: f = 1/(2π√(LC)).")
            card("First order", "A single RC or RL rolls off at 6 dB/octave. Cascade or use LC for steeper slopes — mind loading between stages.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: t); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
