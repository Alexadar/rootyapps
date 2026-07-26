import SwiftUI

struct SRAReferenceView: View {
    var body: some View {
        VStack(spacing: 16) {
            card("Stereo Recording Angle", "The SRA is the width of the sound field in front of a mic pair that maps to the full width between the loudspeakers. Sources outside it collapse toward one side.")
            card("Level + time", "A near-coincident pair images with both an inter-channel level difference (from the polar patterns and angle) and a time difference (from the spacing). Both are computed here exactly.")
            card("Estimate, not a law", "The recording angle combines those two cues with a summing-localization model, calibrated to reproduce the standard rigs (ORTF 96°, NOS 81°, DIN 101°). Perceived width still depends on programme and listener.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: t); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
