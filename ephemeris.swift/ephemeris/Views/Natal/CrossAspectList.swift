import SwiftUI
import EphemerisKit

/// The full cross-aspect list under a bi-wheel.
///
/// The wheel draws only the tightest few — twenty glyphs, two cusp sets and every chord in one
/// circle is unreadable — so the rest are legible here.
///
/// This is also where an unknown birth time stops being an abstraction. When either side lacks a
/// time the orb is not a number, it is a range, and the row says so rather than printing the noon
/// value with false confidence.
struct CrossAspectList: View {
    let chart: SavedChart
    let cross: [CrossAspect]
    /// Present for synastry; nil for transits and progressions, where the moving side is exact.
    var partner: SavedChart? = nil

    @Environment(\.locale) private var locale

    /// Orb ranges keyed by aspect id, computed once for the whole list.
    ///
    /// Built here rather than per row because the sweep is a 97×97 grid when both sides are
    /// untimed, and doing that inside a `ForEach` body would repeat it on every layout pass.
    private var ranges: [String: Uncertainty.OrbRange] {
        guard chart.unknownDay != nil || partner?.unknownDay != nil else { return [:] }
        let ranged = partner.map { chart.rangedSynastry(with: $0) } ?? chart.rangedTransits()
        return Dictionary(uniqueKeysWithValues: ranged.map { ($0.id, $0.orbRange) })
    }

    var body: some View {
        let rows = Array(cross.prefix(12))
        let byId = ranges
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Cross-aspects", trailing: Text(cross.count, format: .number))
            ForEach(rows) { t in
                row(t, range: byId[t.id])
                if t.id != rows.last?.id { NebulaPalette.divider.frame(height: 0.75) }
            }
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.transits")
    }

    private func row(_ t: CrossAspect, range: Uncertainty.OrbRange?) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: t.moving.glyph)
                .foregroundStyle(NebulaPractitioner.outerRingGlyph)
            Text(L.loc(t.type.name)).foregroundStyle(NebulaPalette.textSecondary)
            Text(verbatim: t.reference.glyph)
            Spacer()
            if let range, range.isRange {
                RangeTag(range: range)
            } else {
                Text(verbatim: String(format: "%.2f°", t.orb))
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(NebulaPalette.textSecondary)
            }
        }
        .font(.callout)
        // `.combine` FIRST, then name the result — otherwise macOS fuses the children itself and
        // synthesises a joined identifier that matches nothing.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cross.\(t.moving.rawValue).\(t.reference.rawValue)")
    }
}
