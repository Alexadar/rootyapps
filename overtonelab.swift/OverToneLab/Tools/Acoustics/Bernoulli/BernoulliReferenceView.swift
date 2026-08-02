import SwiftUI

struct BernoulliReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Pipe resonance", "Open–open: f = n·c/2L (all harmonics). Closed–open: f = (2n−1)·c/4L (odd harmonics) — sounds an octave lower for the same length.")
            card("End correction", "An open end radiates a little past the physical opening, lowering pitch: ≈0.61·r unflanged, ≈0.82·r flanged.")
            card("Estimate", "Real bores (tone holes, taper, blowing pressure) diverge — treat as a starting point.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: L.loc(t)); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
