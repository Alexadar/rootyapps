import SwiftUI
import EphemerisKit

/// One saved chart, read four ways.
///
/// The whole point of `MomentReadout`: Positions, Aspects and Houses are not rebuilt here, and
/// neither are the practitioner features. A saved chart is a `SkyMoment`; so is a progressed chart,
/// so is a return, so is a composite. Each facet below changes what feeds the readout, never how it
/// draws — which is why seven Kit features cost four segments instead of seven screens.
///
/// What differs from the live sky is what a chart *has* that a moment does not: an identity, a
/// birth record, and something to compare against.
struct NatalChartView: View {
    @ObservedObject var vm: NatalViewModel
    let chart: SavedChart
    @Environment(\.assistantPresenter) private var presenter

    /// Reel-driven lens and transit ring, passed as **values** rather than as the driver object.
    ///
    /// Holding a plain `ReelDriver?` here did not work and failed silently: an unobserved reference
    /// never re-evaluates the body, so `onChange` never fired, the lens never switched, and the
    /// capture produced a finished 30s video whose last four beats were one frozen screen under
    /// captions promising transits, positions and houses. The parent observes the driver; only the
    /// values it publishes come down here.
    var reelLens: MomentLens? = nil
    var reelTransits: Bool? = nil
    var reelScrollNudge: Int? = nil
    /// Which facet the tour is on, and who it compares against — values, for the same reason.
    var reelFacet: ChartFacet? = nil
    var reelPartner: String? = nil

    @State private var facet: ChartFacet =
        LaunchOverride.value("EPHEMERIS_FACET").flatMap(ChartFacet.init(rawValue:))
        ?? (LaunchOverride.flag("EPHEMERIS_TRANSITS") ? .biwheel : .wheel)
    @State private var source: NebulaPractitioner.BiWheelSource =
        LaunchOverride.value("EPHEMERIS_BIWHEEL").flatMap(NebulaPractitioner.BiWheelSource.init(rawValue:))
        ?? .transits
    @State private var lens: MomentLens =
        LaunchOverride.value("EPHEMERIS_LENS").flatMap(MomentLens.init(rawValue:)) ?? .wheel

    /// The date the bi-wheel compares against — "now" for transits, the scrub target for
    /// progressions. One date for both, because the question "as of when?" is the same question.
    @State private var target = Date()
    @State private var selectedReturn: ReturnEvent?
    @State private var partner: SavedChart?
    @State private var showingPartnerPicker = false
    /// Set once from `EPHEMERIS_PARTNER` so a capture can reach the pairing view, which is
    /// otherwise two taps deep behind a sheet. Applied in `.task`, not in the initialiser: the
    /// library has to have loaded before a UUID prefix can be matched against it.
    @State private var appliedLaunchPartner = false

    @Environment(\.locale) private var locale

    private var facets: ChartFacets { ChartFacets(chart: chart) }

    /// The chart's own `SavedChart` document — the same bytes iCloud stores and `ChartStoreTests`
    /// round-trips — rather than a re-derived summary that could disagree with the file.
    private var exportPayload: ExportPayload {
        ExportPayload(subject: .chart(chart.name),
                      content: .chart(chart),
                      range: DateInterval(start: chart.birthInstant, duration: 1))
    }

    /// A row beneath the wheel, pushing the app's only non-wheel view.
    ///
    /// Per-chart (gate 2), so it belongs here rather than in Sky. ⚠️ With an unknown birth time the
    /// angles are undefined — MC and AC lines simply do not exist — so the row is shown and
    /// **honestly disabled** rather than hidden: hiding it would read as "this app has no
    /// astrocartography", which is a different and wrong statement.
    @ViewBuilder private var astrocartographyRow: some View {
        if chart.isTimeKnown {
            NavigationLink {
                // The observer's own place, for the "near you" distances — read from the shared
                // store rather than threaded through, because it is the same value the widgets use
                // and there is exactly one of it. Nil is fine: the map still draws, without
                // distances.
                ScrollView { AstroMapView(chart: chart, observer: SharedStore().location).padding() }
                    .background(AppBackground())
                    .navigationTitle("Astrocartography")
                    .assistantToolbar()
                    .assistantContext(presenter,
                                      screen: .init(id: "charts.astrocartography",
                                                    title: "Astrocartography")) {
                        ScreenContexts.astrocartography(
                            chart,
                            lines: AstroCartography.lines(at: chart.birthInstant),
                            observer: SharedStore().location, rowLimit: 4)
                    }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.headline).foregroundStyle(NebulaPalette.accent)
                        .frame(width: 30, height: 30)
                        .background(NebulaPalette.accent.opacity(0.15), in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Astrocartography").font(.callout)
                        Text("Where these planets are angular").font(.caption)
                            .foregroundStyle(NebulaPalette.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2)
                        .foregroundStyle(NebulaPalette.textFaint)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .glassCard()
            .accessibilityIdentifier("chart.astrocartography")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                CardHeader(title: "Astrocartography")
                Text("Needs a birth time — the lines are drawn from the angles, which are undefined without one.")
                    .font(.caption).foregroundStyle(NebulaPalette.textSecondary)
            }
            .glassCard()
            .accessibilityIdentifier("chart.astrocartography.unavailable")
        }
    }

    var body: some View {
      ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 16) {
                Color.clear.frame(height: 0).id("top")
                header

                if !chart.isTimeKnown { untimedNotice }

                facetPicker

                switch facet {
                case .wheel:    wheelFacet
                case .biwheel:  biwheelFacet
                case .analysis: AnalysisFacet(facets: facets)
                case .returns:  returnsFacet
                }

                astrocartographyRow

                Color.clear.frame(height: 1).id("bottom")
            }
            .padding()
        }
        // Slow and linear on purpose: this reads as someone scanning the list, not as a UI
        // animation. A spring would overshoot and a fast scroll would defeat the point.
        .onChange(of: reelScrollNudge) { _, _ in
            withAnimation(.easeInOut(duration: 4.0)) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .onChange(of: lens) { _, _ in proxy.scrollTo("top", anchor: .top) }
        .onChange(of: facet) { _, _ in proxy.scrollTo("top", anchor: .top) }
        .background(AppBackground())
        .navigationTitle(Text(verbatim: chart.name))
        .toolbar { compareButton }
        .exportToolbar { exportPayload }
        .assistantToolbar()
        .assistantContext(presenter, screen: .init(id: "charts.natal",
                                                   title: "Birth chart · \(chart.name)")) {
            // The chart's own derived values — the same ones the wheel is drawing, so the
            // explanation and the picture cannot disagree.
            ScreenContexts.natalChart(chart, positions: chart.positions,
                                      aspects: chart.aspects, rowLimit: 4)
        }
        .sheet(isPresented: $showingPartnerPicker) {
            PartnerPicker(vm: vm, subject: chart) { chosen in
                partner = chosen
                showingPartnerPicker = false
            }
        }
        .navigationDestination(item: $partner) { other in
            PairingView(subject: chart, partner: other, houseSystem: $vm.houseSystem)
        }
        .task { openLaunchPartner() }
        .onChange(of: reelLens) { _, new in if let new { lens = new } }
        .onChange(of: reelTransits) { _, new in
            if let new { source = .transits }
        }
        .onChange(of: reelFacet) { _, new in if let new { facet = new } }
        .onChange(of: reelPartner) { _, new in
            // Empty string clears the pairing; a prefix opens it. Matching by prefix, like every
            // other chart deep link here, because the fixtures share a modifiedAt.
            guard let new else { return }
            partner = new.isEmpty ? nil : vm.charts.first {
                $0.id != chart.id && $0.id.uuidString.lowercased().hasPrefix(new.lowercased())
            }
        }
      }
    }

    /// Opens the pairing view straight from the launch environment, for store captures.
    ///
    /// Addressed by UUID prefix, like `EPHEMERIS_CHART`, and for the same reason: the library sorts
    /// by `modifiedAt` and the seeded fixtures share an instant, so a row index picks a different
    /// person per run. `LaunchOverride` is DEBUG-gated, so this is inert in a shipping build.
    private func openLaunchPartner() {
        guard !appliedLaunchPartner, partner == nil,
              let wanted = LaunchOverride.value("EPHEMERIS_PARTNER")?.lowercased()
        else { return }
        appliedLaunchPartner = true
        partner = vm.charts.first {
            $0.id != chart.id && $0.id.uuidString.lowercased().hasPrefix(wanted)
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The birth moment and place ARE what make this a natal chart rather than just a
            // chart, so they read as content, not as a footnote.
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var untimedNotice: some View {
        HonestStateCard(
            title: L.string("Birth time unknown", locale: locale),
            explanation: L.string(
                "Positions still compute. Houses, angles and anything derived from them are left out rather than calculated from an assumed noon.",
                locale: locale))
        .accessibilityIdentifier("state.timeUnknown")
    }

    private var facetPicker: some View {
        Picker("Chart", selection: $facet) {
            ForEach(ChartFacet.allCases) { f in
                Label(f.title, systemImage: f.icon).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier(NebulaPractitioner.A11y.facet)
    }

    @ToolbarContentBuilder
    private var compareButton: some ToolbarContent {
        ToolbarItem {
            Button {
                showingPartnerPicker = true
            } label: {
                Label {
                    Text("Compare")
                } icon: {
                    Text(verbatim: NebulaPractitioner.compareGlyph)
                }
            }
            .accessibilityIdentifier(NebulaPractitioner.A11y.compare)
        }
    }

    // MARK: - Facets

    private var wheelFacet: some View {
        MomentReadout(moment: SkyMoment(positions: chart.positions,
                                        aspects: chart.aspects,
                                        houses: vm.houses,
                                        houseFallback: nil,
                                        outerPositions: nil,
                                        crossAspects: []),
                      lens: $lens,
                      houseSystem: $vm.houseSystem,
                      heading: "Natal chart")
    }

    @ViewBuilder
    private var biwheelFacet: some View {
        VStack(spacing: 16) {
            Picker("Bi-wheel", selection: $source) {
                ForEach(NebulaPractitioner.BiWheelSource.allCases) { s in
                    Text(verbatim: L.string(s.titleKey, locale: locale)).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier(NebulaPractitioner.A11y.biwheelSource)

            switch source {
            case .transits:
                biwheel(outer: facets.transitPositions(at: target),
                        cross: chart.transits(at: target),
                        caption: nil)
            case .progressed:
                let p = facets.progressed(to: target)
                biwheel(outer: p.positions,
                        cross: Aspects.detect(between: p.positions, and: chart.positions, orbFactor: 1.0),
                        caption: progressedCaption(p))
            case .chartReturn:
                if let event = selectedReturn ?? facets.returnCycles().first {
                    biwheel(outer: facets.returnPositions(for: event),
                            cross: Aspects.detect(between: facets.returnPositions(for: event),
                                                  and: chart.positions, orbFactor: 1.0),
                            caption: returnCaption(event))
                } else {
                    HonestStateCard(
                        title: L.string("No return available", locale: locale),
                        explanation: L.string(
                            "No solar, lunar or Saturn return falls inside the verified window.",
                            locale: locale))
                }
            case .partner:
                if let other = partner {
                    biwheel(outer: other.positions,
                            cross: chart.synastry(with: other),
                            caption: Text(verbatim: "\(chart.name) \(NebulaPractitioner.compareGlyph) \(other.name)"))
                } else {
                    HonestStateCard(
                        title: L.string("No partner chosen", locale: locale),
                        explanation: L.string(
                            "Pick a second chart to compare against this one.",
                            locale: locale),
                        fixLabel: L.string("Choose a partner", locale: locale),
                        onFix: { showingPartnerPicker = true })
                }
            }
        }
    }

    private func biwheel(outer: [BodyPosition], cross: [CrossAspect], caption: Text?) -> some View {
        VStack(spacing: 10) {
            if let caption {
                caption
                    .font(.caption)
                    .foregroundStyle(NebulaPalette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            MomentReadout(moment: SkyMoment(positions: chart.positions,
                                            aspects: chart.aspects,
                                            houses: vm.houses,
                                            houseFallback: nil,
                                            outerPositions: outer,
                                            crossAspects: cross),
                          lens: $lens,
                          houseSystem: $vm.houseSystem,
                          heading: "Natal chart")
            CrossAspectList(chart: chart, cross: cross, partner: partner)
        }
    }

    private func progressedCaption(_ p: ProgressedChart) -> Text {
        Text(verbatim: L.string("Progressed to", locale: locale) + " ")
            + Text(p.target, format: .dateTime.day().month(.abbreviated).year())
            + Text(verbatim: " · " + String(format: "%.1f", p.ageYears) + " ")
            + Text(verbatim: L.string("years", locale: locale))
    }

    private func returnCaption(_ e: ReturnEvent) -> Text {
        Text(verbatim: e.body.glyph + " ")
            + Text(verbatim: L.string("Return", locale: locale) + " · ")
            + Text(e.date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
    }

    private var returnsFacet: some View {
        ReturnsList(facets: facets,
                    selected: $selectedReturn,
                    onOpen: { event in
                        selectedReturn = event
                        source = .chartReturn
                        facet = .biwheel
                    },
                    watchDefault: watchDefaultControl)
    }

    /// Offered only on iOS, and only for a chart the watch could actually use.
    private var watchDefaultControl: (isDefault: Bool, toggle: () -> Void)? {
#if os(iOS)
        guard chart.isTimeKnown else { return nil }
        let isDefault = vm.defaultChartID == chart.id
        return (isDefault, { vm.setDefaultChart(isDefault ? nil : chart) })
#else
        nil
#endif
    }
}
