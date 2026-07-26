import SwiftUI

struct WebsterReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Exponential horn", "Area grows as A(x) = A₀·e^{m·x}. Cutoff fc = c·m/4π; below it the horn stops loading the driver. Flare constant m = ln(A_mouth/A_throat)/L.")
            card("Helmholtz", "A neck of air on a cavity spring: f = (c/2π)·√(A / (V·L_eff)). Governs bass-reflex ports, bottles and ocarinas.")
            card("Model caveat", "1-D Webster theory — real horns depend on mouth size, rate of flare and room loading. Cross-check serious designs in Hornresp.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: L.loc(t)); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
