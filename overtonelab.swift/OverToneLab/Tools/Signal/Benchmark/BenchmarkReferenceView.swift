import SwiftUI

struct BenchmarkReferenceView: View {
    private let targets: [(String, String)] = [
        ("Spotify / YouTube / Tidal", "−14 LUFS"),
        ("Apple Music", "−16 LUFS"),
        ("Amazon Music", "−14 LUFS"),
        ("EBU R128 (broadcast)", "−23 LUFS"),
        ("Club / loud CD master", "−9 to −7 LUFS"),
    ]
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Streaming targets")
                ForEach(targets, id: \.0) { t in
                    HStack { Text(t.0).font(.callout); Spacer(); Text(t.1).monospacedDigit().foregroundStyle(.secondary) }
                }
            }.glassCard()
            card("Integrated LUFS", "BS.1770 K-weights the audio, splits it into 400 ms blocks (75% overlap), gates out silence (−70 LUFS absolute, −10 LU relative), and averages what remains.")
            card("LU = dB", "One loudness unit equals one decibel of gain. Match a target by applying the difference — but keep true-peak below −1 dBTP to avoid clipping.")
        }
    }
    private func card(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { CardHeader(title: t); Text(b).font(.callout).foregroundStyle(.secondary) }.glassCard()
    }
}
