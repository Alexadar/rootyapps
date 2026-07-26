import SwiftUI
import EphemerisKit

/// Stage 3 — aspects computed from the positions.
struct AspectsList: View {
    let aspects: [DetectedAspect]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Aspects", trailing: "\(aspects.count)")
            if aspects.isEmpty {
                Text("No aspects within the current orb.")
                    .font(.callout).foregroundStyle(NebulaPalette.textSecondary).italic()
            } else {
                ForEach(aspects) { a in
                    HStack(spacing: 10) {
                        Text(a.type.glyph + "\u{FE0E}")
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(a.type.color, in: .rect(cornerRadius: 6))
                        Text("\(a.a.glyph) \(a.a.name)")
                        Text(a.type.name).foregroundStyle(NebulaPalette.textSecondary)
                        Text("\(a.b.glyph) \(a.b.name)")
                        Spacer()
                        Text(String(format: "orb %.2f°", a.orb))
                            .font(.caption).monospacedDigit().foregroundStyle(NebulaPalette.textSecondary)
                    }
                    .font(.callout)
                }
            }
        }
        .glassCard()
    }
}
