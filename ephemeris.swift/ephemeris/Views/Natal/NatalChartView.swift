import SwiftUI
import EphemerisKit

/// One saved chart, read through exactly the same four lenses as the live sky.
///
/// The whole point of `MomentReadout`: Positions, Aspects and Houses are not rebuilt here. A saved
/// chart is simply a different `SkyMoment` — a frozen instant instead of a live one — so the two
/// halves of the app cannot drift apart about how a chart is drawn.
///
/// What differs is what a chart *has* that the live sky does not: an identity, a birth record, and
/// something to compare against.
struct NatalChartView: View {
    @ObservedObject var vm: NatalViewModel
    let chart: SavedChart
    /// Reel-driven lens and transit ring, passed as **values** rather than as the driver object.
    ///
    /// Holding a plain `ReelDriver?` here did not work and failed silently: an unobserved reference
    /// never re-evaluates the body, so `onChange` never fired, the lens never switched, and the
    /// capture produced a finished 30s video whose last four beats were one frozen screen under
    /// captions promising transits, positions and houses. The parent observes the driver; only the
    /// values it publishes come down here.
    var reelLens: MomentLens? = nil
    var reelTransits: Bool? = nil
    /// Bumped by the tour to scroll the current reading. A value, not the driver — see above.
    var reelScrollNudge: Int? = nil

    /// What the outer ring shows. Transits are a comparison, not another lens — they need two
    /// moments at once, which is why they belong here rather than inside `MomentLens`.
    enum Comparison: String, CaseIterable, Identifiable {
        case none, transits
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            // Short, like every other segment. The long form is the heading below.
            case .none:     "Natal"
            case .transits: "Transits"
            }
        }
    }

    /// Both seeded from the launch environment so a store capture can open straight onto, say, the
    /// bi-wheel — one shot per launch, no tapping, nothing to race. Absent (and always in Release,
    /// since `LaunchOverride` is DEBUG-gated) these fall back to the real defaults a user sees.
    @State private var comparison: Comparison =
        LaunchOverride.flag("EPHEMERIS_TRANSITS") ? .transits : .none
    @State private var lens: MomentLens =
        LaunchOverride.value("EPHEMERIS_LENS").flatMap(MomentLens.init(rawValue:)) ?? .wheel

    private var moment: SkyMoment {
        SkyMoment(positions: chart.positions,
                  aspects: chart.aspects,
                  houses: vm.houses,
                  houseFallback: nil,
                  outerPositions: comparison == .transits ? vm.transitPositions : nil,
                  crossAspects: comparison == .transits ? vm.transits : [])
    }

    var body: some View {
      ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 16) {
                Color.clear.frame(height: 0).id("top")
                header

                if !chart.isTimeKnown {
                    Text("Houses and angles need a birth time.")
                        .font(.callout)
                        .foregroundStyle(NebulaPalette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                        .accessibilityIdentifier("state.timeUnknown")
                }

                MomentReadout(moment: moment, lens: $lens, houseSystem: $vm.houseSystem,
                              heading: "Natal chart")

                if comparison == .transits { transitList }
                Color.clear.frame(height: 1).id("bottom")
            }
            .padding()
        }
        // Slow and linear on purpose: this is meant to read as someone scanning the list, not as a
        // UI animation. A spring would overshoot and a fast scroll would defeat the point.
        .onChange(of: reelScrollNudge) { _, _ in
            withAnimation(.easeInOut(duration: 4.0)) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        // Every lens starts at the top, or the next list opens already scrolled and its heading is
        // never seen.
        .onChange(of: lens) { _, _ in proxy.scrollTo("top", anchor: .top) }
        .background(AppBackground())
        .navigationTitle(Text(verbatim: chart.name))
        .onChange(of: reelLens) { _, new in if let new { lens = new } }
        .onChange(of: reelTransits) { _, new in
            if let new { comparison = new ? .transits : .none }
        }
      }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Natal chart", selection: $comparison) {
                ForEach(Comparison.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("input.comparison")

            // The birth moment and place ARE what make this a natal chart rather than just a chart,
            // so they read as content, not as a footnote. Previously caption-grey and easy to miss.
            HStack(spacing: 6) {
                Image(systemName: "smallcircle.filled.circle")
                    .font(.caption2)
                    .foregroundStyle(NebulaPalette.accent)
                Text(chart.birthInstant, format: .dateTime.day().month(.wide).year())
                if chart.isTimeKnown {
                    Text(chart.birthInstant, format: .dateTime.hour().minute())
                }
                if let place = chart.placeName { Text(verbatim: "· " + place) }
            }
            .font(.subheadline)
            .foregroundStyle(NebulaPalette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    /// The full cross-aspect list. The wheel draws only the tightest few — twenty glyphs, two cusp
    /// sets and every chord in one circle is unreadable — so the rest are legible here.
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
