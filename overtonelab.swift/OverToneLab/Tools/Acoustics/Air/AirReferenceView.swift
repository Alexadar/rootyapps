import SwiftUI

struct AirReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Air absorption", "Beyond the inverse-square distance law, air itself attenuates sound — strongly at high frequencies and low humidity. ISO 9613-1 gives the pure-tone coefficient from temperature, humidity and pressure.")
            card("Why it matters", "Over long PA throws and delay-tower distances the top end is eaten away; account for it when aligning and EQ-ing far fills.")
            card("Estimate", "Still, homogeneous air only. Wind, temperature gradients and turbulence outdoors shift the real figure — treat as a planning estimate.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: L.loc(t)); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
