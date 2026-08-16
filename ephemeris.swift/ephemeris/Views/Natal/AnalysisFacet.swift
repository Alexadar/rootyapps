import SwiftUI
import EphemerisKit

/// What a chart is made of: dignities, shape, elemental and modal balance, midpoints.
///
/// Four features share this facet because they answer one question — "what kind of chart is this?"
/// — and none of them needs a wheel. Giving each its own destination would put four taps between
/// the practitioner and four cards that fit on one screen.
struct AnalysisFacet: View {
    let facets: ChartFacets
    @State private var showAllMidpoints = false
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 16) {
            dignitiesCard
            shapeCard
            balancesCard
            midpointsCard
        }
    }

    // MARK: - Dignities

    private var dignitiesCard: some View {
        let rows = facets.dignities
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Essential dignities")

            if facets.sectIsAssumed {
                // Sect is diurnal-vs-nocturnal, which needs to know whether the Sun was above the
                // horizon — which needs a birth time. Triplicity rulers differ by sect, so this
                // changes scores. Saying so is cheaper than being quietly wrong.
                HonestStateCard(
                    title: L.string("Sect assumed", locale: locale),
                    explanation: L.string(
                        "Without a birth time the day tables are used. Triplicity rulers differ between day and night charts, so these scores may shift.",
                        locale: locale))
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { _, entry in
                dignityRow(entry.score, alternative: entry.alternative)
                NebulaPalette.divider.frame(height: 0.75)
            }
            if rows.isEmpty {
                Text("The classical tables assign nothing to the modern planets.")
                    .font(.caption)
                    .foregroundStyle(NebulaPalette.textSecondary)
            }
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(NebulaPractitioner.A11y.analysisDignities)
    }

    private func dignityRow(_ s: DignityScore, alternative: DignityScore?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(verbatim: s.body.glyph)
                SignChip(glyph: s.sign.glyph, size: 20)
                Text(L.loc(s.sign.name))
                    .foregroundStyle(NebulaPalette.textSecondary)
                Spacer()
                Text(verbatim: s.total > 0 ? "+\(s.total)" : "\(s.total)")
                    .font(.callout.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(s.total < 0 ? NebulaPalette.retrograde : NebulaPalette.accentGreen)
            }
            .font(.callout)

            Text(verbatim: s.kinds.map { L.string($0.name, locale: locale) }
                    .joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(NebulaPalette.textFaint)

            // Both candidates, when the unknown birth time leaves the sign undetermined. Choosing
            // one would be a coin toss presented as a result.
            if let alternative {
                HStack(spacing: 6) {
                    Text(verbatim: L.string("or", locale: locale))
                        .font(NebulaPractitioner.rangeTagFont)
                        .foregroundStyle(NebulaPractitioner.warn)
                    SignChip(glyph: alternative.sign.glyph, size: 17)
                    Text(L.loc(alternative.sign.name))
                    Spacer()
                    Text(verbatim: alternative.total > 0 ? "+\(alternative.total)" : "\(alternative.total)")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(NebulaPalette.textSecondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(NebulaPractitioner.warnFill, in: .rect(cornerRadius: 8))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dignity.\(s.body.rawValue)")
    }

    // MARK: - Shape

    private var shapeCard: some View {
        let analysis = facets.analysis
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Shape")
            if let shape = analysis.shape {
                Text(L.loc(shape.pattern.rawValue.capitalized))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NebulaPalette.textPrimary)
                if !analysis.handleBodies.isEmpty {
                    Text(verbatim: L.string("Handle", locale: locale) + ": "
                         + analysis.handleBodies.map(\.glyph).joined(separator: " "))
                        .font(.callout)
                        .foregroundStyle(NebulaPalette.textSecondary)
                }
            } else {
                Text("No recognised pattern.")
                    .font(.callout)
                    .foregroundStyle(NebulaPalette.textSecondary)
            }
            if !analysis.unaspected.isEmpty {
                Text(verbatim: L.string("Unaspected", locale: locale) + ": "
                     + analysis.unaspected.map(\.glyph).joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(NebulaPalette.textFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(NebulaPractitioner.A11y.analysisShape)
    }

    // MARK: - Balances

    private var balancesCard: some View {
        let analysis = facets.analysis
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Balance")
            balanceRow(title: L.string("Elements", locale: locale),
                       pairs: analysis.elements.ordered.map { (L.string($0.key.rawValue.capitalized, locale: locale), $0.count) },
                       total: analysis.elements.total)
            NebulaPalette.divider.frame(height: 0.75)
            balanceRow(title: L.string("Modalities", locale: locale),
                       pairs: analysis.modalities.ordered.map { (L.string($0.key.rawValue.capitalized, locale: locale), $0.count) },
                       total: analysis.modalities.total)
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(NebulaPractitioner.A11y.analysisBalances)
    }

    private func balanceRow(title: String, pairs: [(String, Int)], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(NebulaPalette.textHead)
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                HStack(spacing: 8) {
                    Text(verbatim: pair.0)
                        .frame(width: 82, alignment: .leading)
                    // A bar, because the point of a balance is the comparison, and eight numbers
                    // in a column make the reader do the comparing.
                    GeometryReader { geo in
                        Capsule()
                            .fill(NebulaPalette.accent.opacity(pair.1 == 0 ? 0.15 : 0.65))
                            .frame(width: max(2, geo.size.width * ratio(pair.1, total)))
                    }
                    .frame(height: 7)
                    Text(verbatim: "\(pair.1)")
                        .monospacedDigit()
                        .frame(width: 18, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(NebulaPalette.textSecondary)
            }
        }
    }

    private func ratio(_ n: Int, _ total: Int) -> Double {
        total > 0 ? Double(n) / Double(total) : 0
    }

    // MARK: - Midpoints

    private var midpointsCard: some View {
        let pairs = facets.midpoints(personalOnly: !showAllMidpoints)
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Midpoints", trailing: Text(pairs.count, format: .number))
            ForEach(pairs) { pair in
                midpointRow(pair)
                NebulaPalette.divider.frame(height: 0.75)
            }
            Button {
                showAllMidpoints.toggle()
            } label: {
                Text(showAllMidpoints ? "Personal planets only" : "All pairs")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(NebulaPalette.accentCyan)
            .accessibilityIdentifier("analysis.midpoints.toggle")
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(NebulaPractitioner.A11y.analysisMidpoints)
    }

    private func midpointRow(_ p: ChartFacets.MidpointPair) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: "\(p.a.glyph)/\(p.b.glyph)")
            Spacer()
            // Both ends of the axis: a planet on either activates it, so showing only one half
            // hides half the technique.
            Text(verbatim: format(p.longitude))
                .monospacedDigit()
            Text(verbatim: "·")
                .foregroundStyle(NebulaPalette.textFaint)
            Text(verbatim: format(p.opposite))
                .monospacedDigit()
                .foregroundStyle(NebulaPalette.textSecondary)
        }
        .font(.callout)
        // Kept and flagged rather than dropped — a missing row is indistinguishable from a pair
        // that has no midpoint, and these have two equally valid ones.
        .padding(.vertical, p.isAmbiguous ? 4 : 0)
        .background(p.isAmbiguous ? NebulaPractitioner.midpointAmbiguousRowFill : .clear)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("midpoint.\(p.a.rawValue).\(p.b.rawValue)")
    }

    private func format(_ longitude: Double) -> String {
        let sign = ZodiacSign.from(longitude: longitude)
        let deg = longitude.truncatingRemainder(dividingBy: 30)
        return String(format: "%@ %.0f°", sign.glyph, deg)
    }
}
