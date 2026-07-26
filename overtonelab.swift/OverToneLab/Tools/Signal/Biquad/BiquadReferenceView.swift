import SwiftUI

struct BiquadReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Biquad filters", "A 2nd-order IIR section: H(z) = (b0 + b1z⁻¹ + b2z⁻²) / (1 + a1z⁻¹ + a2z⁻²). Coefficients are a₀-normalized — paste them straight into a DSP/plug-in.")
            card("RBJ Audio EQ Cookbook", "Low/high-pass, band-pass, notch, all-pass, peaking and shelving forms follow Robert Bristow-Johnson's cookbook. Peaking sits exactly at its set gain at f₀; shelves reach their gain at the far band edge.")
            card("Q and f₀", "Q sets the resonance/bandwidth; f₀ the corner or centre. Keep f₀ below the Nyquist frequency (fs⁄2), or the response wraps.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: t); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
