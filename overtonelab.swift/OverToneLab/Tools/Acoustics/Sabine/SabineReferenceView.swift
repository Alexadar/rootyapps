import SwiftUI

struct SabineReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Reverberation (RT60)", "Time for sound to decay 60 dB. Sabine: 0.161·V/A. Eyring is more accurate when average absorption is high.")
            card("Modes & Schroeder", "Axial room modes (n·c/2L) colour the low end; above the Schroeder frequency the room is statistically diffuse.")
            card("Estimate, not measurement", "Real rooms diverge — diffusion, non-uniform absorption, furnishings. Cross-check with a measurement.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: L.loc(t)); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
