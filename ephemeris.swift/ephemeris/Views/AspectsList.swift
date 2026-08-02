import SwiftUI
import EphemerisKit

/// Stage 3 — aspects computed from the positions.
struct AspectsList: View {
    let aspects: [DetectedAspect]
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Aspects", trailing: Text(aspects.count, format: .number))
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
                        // Glyph verbatim + name resolved through the catalog, joined as one
                        // String. Interpolating both into `Text("\(glyph) \(name)")` would make
                        // the whole thing a format-string key, which misses and leaves the Kit's
                        // English body name on screen.
                        Text(verbatim: a.a.glyph + " " + L.string(a.a.name, locale: locale))
                        Text(L.loc(a.type.name)).foregroundStyle(NebulaPalette.textSecondary)
                        Text(verbatim: a.b.glyph + " " + L.string(a.b.name, locale: locale))
                        Spacer()
                        // `String(format:)` hardcodes a "." separator; most of Europe writes "1,25".
                        // Interpolating a pre-formatted String keeps the extracted key a plain
                        // "orb %@°" rather than a numeric specifier that varies by platform.
                        Text("orb \(a.orb.formatted(.number.precision(.fractionLength(2)).locale(locale)))°")
                            .font(.caption).monospacedDigit().foregroundStyle(NebulaPalette.textSecondary)
                            // Body rawValues, so the key survives localization and reordering.
                            .accessibilityIdentifier("aspect.\(a.a.rawValue).\(a.b.rawValue).orb")
                    }
                    .font(.callout)
                }
            }
        }
        .glassCard()
        // `.contain`, not `.combine`: combining fuses every row into one element and macOS then
        // publishes a single joined identifier, leaving no leaf to query (trap 4).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.aspects")
    }
}
