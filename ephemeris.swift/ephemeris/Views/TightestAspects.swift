import SwiftUI
import EphemerisKit

/// The few closest aspects, beside the wheel that draws them.
///
/// Nebula v2 puts this on the Chart screen because the wheel shows aspect chords as *lines* — you
/// can see that Mars and Saturn are connected, but not that they are 0.4° from exact, and exactness
/// is the whole of an aspect's strength. The full list lives on its own tab; this is the summary
/// that makes the wheel readable without leaving it.
///
/// `Aspects.detect` already returns them sorted by orb, so "tightest" is just the head of the list —
/// no second sort, and no risk of the two views disagreeing about ordering.
struct TightestAspects: View {
    let aspects: [DetectedAspect]
    /// Five fits the card without scrolling at every width the app ships on.
    var limit: Int = 5

    @Environment(\.locale) private var locale

    private var shown: [DetectedAspect] { Array(aspects.prefix(limit)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Tightest aspects", trailing: Text(aspects.count, format: .number))

            if shown.isEmpty {
                Text("No aspects within the current orb.")
                    .font(.callout).foregroundStyle(NebulaPalette.textSecondary).italic()
            } else {
                ForEach(shown) { a in
                    HStack(spacing: 10) {
                        Text(a.type.glyph + "\u{FE0E}")
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(a.type.color, in: .rect(cornerRadius: 6))
                        // Glyph verbatim, name through the catalog, joined as one String — the same
                        // construction AspectsList uses. Interpolating both into a single `Text`
                        // would make the whole thing a format-string key and leave the Kit's
                        // English body name on screen.
                        Text(verbatim: a.a.glyph + " " + L.string(a.a.name, locale: locale))
                        Text(L.loc(a.type.name)).foregroundStyle(NebulaPalette.textSecondary)
                        Text(verbatim: a.b.glyph + " " + L.string(a.b.name, locale: locale))
                        Spacer()
                        Text(a.orb.formatted(.number.precision(.fractionLength(2)).locale(locale)) + "°")
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(NebulaPalette.textSecondary)
                            .accessibilityIdentifier("tightest.\(a.a.rawValue).\(a.b.rawValue).orb")
                    }
                    .font(.callout)
                }
            }
        }
        .glassCard()
        // `.contain`, not `.combine`: combining fuses the rows into one element and macOS then
        // publishes a single joined identifier, leaving no leaf to query.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.tightestAspects")
    }
}
