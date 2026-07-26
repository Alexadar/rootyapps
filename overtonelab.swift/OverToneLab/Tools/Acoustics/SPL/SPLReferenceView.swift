import SwiftUI

struct SPLReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Inverse-square law", "In a free field, sound spreads over a growing sphere: L₂ = L₁ − 20·log₁₀(r₂/r₁). −6 dB per doubling of distance.")
            card("Adding sources", "Uncorrelated sources add on a power basis (+3 dB for two equal); in-phase coherent sources add on pressure (+6 dB).")
            card("Reality", "Rooms, boundaries and directivity change this — the free-field law is the starting estimate, not a room prediction.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: t); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
