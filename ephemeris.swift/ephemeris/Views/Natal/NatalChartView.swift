import SwiftUI
import EphemerisKit



/// One saved chart, shown with the same cards the "now" sections use.
///
/// This is why natal is a *section* and not a mode. `ChartWheel`, `PositionsTable`, `AspectsList`
/// and `TightestAspects` all take plain data, so a saved chart gets full depth here without a
/// single existing screen changing — which keeps the shipped screenshots valid and avoids the
/// contradiction a scoped Moment card would create (a birth instant is immutable; the Moment card
/// exists to move it).
struct NatalChartView: View {
    @ObservedObject var vm: NatalViewModel
    let chart: SavedChart

    /// What the outer ring shows, if anything. Transits and synastry are comparisons, not variants,
    /// so they belong here rather than as separate destinations.
    enum Comparison: String, CaseIterable, Identifiable {
        case none, transits
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .none:     "Natal chart"
            case .transits: "Transits"
            }
        }
    }
    @State private var comparison: Comparison = .none

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                // Bi-wheel when comparing: natal inside, transiting outside, and only the tightest
                // cross-chords drawn — the rest are in the list below, where they are readable.
                ChartWheel(positions: chart.positions,
                           aspects: chart.aspects,
                           houses: vm.houses,
                           outerPositions: comparison == .transits ? vm.transitPositions : nil,
                           crossAspects: comparison == .transits ? vm.transits : [])

                if !chart.isTimeKnown {
                    Text("Houses and angles need a birth time.")
                        .font(.callout)
                        .foregroundStyle(NebulaPalette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                        .accessibilityIdentifier("state.timeUnknown")
                }

                TightestAspects(aspects: chart.aspects)
                PositionsTable(positions: chart.positions)

                if comparison == .transits {
                    transitList
                }
            }
            .padding()
        }
        .background(AppBackground())
        .navigationTitle(Text(verbatim: chart.name))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Natal chart", selection: $comparison) {
                ForEach(Comparison.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("input.comparison")

            HStack(spacing: 6) {
                Text(chart.birthInstant, format: .dateTime.day().month(.abbreviated).year())
                if chart.isTimeKnown {
                    Text(chart.birthInstant, format: .dateTime.hour().minute())
                }
                if let place = chart.placeName { Text(verbatim: "· " + place) }
            }
            .font(.caption)
            .foregroundStyle(NebulaPalette.textSecondary)
        }
        .glassCard()
    }

    /// Transiting bodies against natal ones. `CrossAspect` names which side is which, so a Saturn
    /// return reads as transiting Saturn on natal Saturn rather than as a nonsensical self-aspect.
    private var transitList: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Transits", trailing: Text(vm.transits.count, format: .number))
            ForEach(Array(vm.transits.prefix(12).enumerated()), id: \.offset) { _, t in
                HStack(spacing: 10) {
                    Text(verbatim: t.moving.glyph)
                    Text(L.loc(t.type.name)).foregroundStyle(NebulaPalette.textSecondary)
                    Text(verbatim: t.reference.glyph)
                    Spacer()
                    Text(verbatim: String(format: "%.2f°", t.orb))
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(NebulaPalette.textSecondary)
                }
                .font(.callout)
            }
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.transits")
    }
}
