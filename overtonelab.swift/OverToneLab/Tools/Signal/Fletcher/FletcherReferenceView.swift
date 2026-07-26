import SwiftUI

struct FletcherReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Frequency weighting", "A/C/Z curves (IEC 61672) model how loud a tone seems at each frequency. A-weighting matches quiet-level hearing and is normalised to 0 dB at 1 kHz.")
            card("When to use which", "A for everyday noise/level metering, C for peaks and low-frequency content, Z (flat/none) for raw measurement.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: L.loc(t)); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
