import SwiftUI

struct ButterworthReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Butterworth", "Maximally-flat passband: |H| = 1/√(1 + (f/fc)^{2n}). Exactly −3.01 dB at fc; rolls off toward 6n dB/octave.")
            card("Linkwitz-Riley", "Two cascaded Butterworth sections (order 2n). Each branch is −6 dB at the crossover and in phase, so a two-way sums to a flat response.")
            card("Model caveat", "Ideal transfer functions. Real components (tolerance, ESR, driver impedance and Q) shift fc and Q — measure to confirm.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: L.loc(t)); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
