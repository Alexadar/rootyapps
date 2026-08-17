import SwiftUI
import EphemerisKit

/// Choosing the second chart.
///
/// Deliberately a sheet from an open chart rather than multi-select in the library. Multi-select is
/// the obvious answer and the wrong one: it needs an edit mode, a selection count and a confirm
/// action, and it models the pair as symmetric when a practitioner's question never is — it is
/// always "this client, against whom?". Here side A is already decided by where the user came from,
/// so the sheet asks exactly one question.
struct PartnerPicker: View {
    @ObservedObject var vm: NatalViewModel
    let subject: SavedChart
    var onPick: (SavedChart) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// Everything except the chart we came from. Comparing a chart with itself is not a question
    /// anyone asks, and every cross-aspect would be an exact conjunction.
    private var candidates: [SavedChart] {
        vm.charts.filter { $0.id != subject.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    // The library empty-state, not an empty table: "no charts" and "no *other*
                    // charts" are different facts and the second one has an obvious next step.
                    ContentUnavailableView {
                        Label("Save another chart", systemImage: "person.crop.circle.badge.plus")
                    } description: {
                        Text("Comparing needs two charts. This is the only one saved.")
                    }
                    .accessibilityIdentifier("state.needSecondChart")
                } else {
                    list
                }
            }
            .navigationTitle(Text(verbatim: L.string("Compare with", locale: locale)))
            .toolbar {
                Button("Cancel") { dismiss() }
            }
            // Named here, on the content, and marked as a container first.
            //
            // The identifier was on the `NavigationStack` and on macOS that is a no-op — an
            // identifier on a bare container publishes nothing, so the picker was unaddressable
            // there while passing on iOS. Same trap as the natal rows.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(NebulaPractitioner.A11y.partnerPicker)
        }
        // A sheet on macOS takes its size from its content, and a `List` offers none — so the rows
        // laid out below the visible area and were not hittable, which is a real defect and not a
        // test artifact: a user could not have clicked them either. iOS sizes sheets itself.
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 380, idealHeight: 520)
        #endif
    }

    private var list: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    SideBadge(side: .a)
                    Text(verbatim: subject.name).font(.headline)
                }
                .listRowBackground(Color.clear)
            } header: {
                Text("This chart")
            }

            Section {
                ForEach(candidates) { chart in
                    Button {
                        RecentPairs.remember(subject.id, chart.id)
                        onPick(chart)
                    } label: {
                        HStack(spacing: 8) {
                            SideBadge(side: .b)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: chart.name).font(.headline)
                                HStack(spacing: 6) {
                                    Text(chart.birthInstant,
                                         format: .dateTime.day().month(.abbreviated).year())
                                    if let place = chart.placeName { Text(verbatim: "· " + place) }
                                    if !chart.isTimeKnown {
                                        Text("Birth time unknown")
                                            .foregroundStyle(NebulaPalette.retrograde)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(NebulaPalette.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("partner.\(chart.id.uuidString)")
                }
            } header: {
                Text(recentFirst.isEmpty ? "Charts" : "Recent")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
    }

    /// Recently paired charts float to the top, so the second consultation of a couple is two taps.
    private var recentFirst: [UUID] { RecentPairs.partners(of: subject.id) }
}

/// Which side of a pairing a chart is on. A is always where the user came from.
enum PairSide {
    case a, b
    var color: Color { self == .a ? NebulaPractitioner.sideA : NebulaPractitioner.sideB }
    var label: String { self == .a ? "A" : "B" }
}

struct SideBadge: View {
    let side: PairSide
    var body: some View {
        Text(verbatim: side.label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(side.color, in: .circle)
            .accessibilityHidden(true)
    }
}

/// The pairs this device has looked at, most recent first.
///
/// Stored as identifier pairs in `UserDefaults` rather than in the chart files: which pairs someone
/// consulted recently is a property of *this device's* browsing, not of the charts, and writing it
/// into an iCloud document would sync one person's UI history onto their other devices and into a
/// file they can open.
enum RecentPairs {
    private static let key = "ephemeris.recentPairs"

    static func remember(_ a: UUID, _ b: UUID) {
        var pairs = load()
        let entry = [a.uuidString, b.uuidString]
        pairs.removeAll { Set($0) == Set(entry) }
        pairs.insert(entry, at: 0)
        if pairs.count > NebulaPractitioner.recentPairsLimit {
            pairs = Array(pairs.prefix(NebulaPractitioner.recentPairsLimit))
        }
        UserDefaults.standard.set(pairs, forKey: key)
    }

    static func partners(of id: UUID) -> [UUID] {
        load().compactMap { pair in
            guard pair.contains(id.uuidString) else { return nil }
            return pair.first { $0 != id.uuidString }.flatMap(UUID.init(uuidString:))
        }
    }

    private static func load() -> [[String]] {
        UserDefaults.standard.array(forKey: key) as? [[String]] ?? []
    }
}

// MARK: - The pairing itself

/// Two charts, read two ways.
///
/// Synastry and composite are two readings of the same pair, not two features — so they are
/// segments of one view rather than two destinations. Both render through the shared
/// `MomentReadout`: a composite is a synthetic moment, and synastry is a bi-wheel.
struct PairingView: View {
    let subject: SavedChart
    let partner: SavedChart
    @Binding var houseSystem: HouseSystem

    enum Reading: String, CaseIterable, Identifiable {
        case synastry, composite
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .synastry:  "Synastry"
            case .composite: "Composite"
            }
        }
    }

    @State private var reading: Reading = .synastry
    @State private var lens: MomentLens = .wheel
    @Environment(\.locale) private var locale

    private var composite: CompositeChart {
        Composite.chart(of: subject.positions, and: partner.positions,
                        angles: subject.isTimeKnown ? subject.houses(system: houseSystem)?.angles : nil,
                        and: partner.isTimeKnown ? partner.houses(system: houseSystem)?.angles : nil)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                sides
                Picker("Reading", selection: $reading) {
                    ForEach(Reading.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier(NebulaPractitioner.A11y.pairingSynastry)

                switch reading {
                case .synastry:  synastry
                case .composite: compositeView
                }
            }
            .padding()
        }
        .background(AppBackground())
        .navigationTitle(Text(verbatim:
            "\(subject.name) \(NebulaPractitioner.compareGlyph) \(partner.name)"))
    }

    private var sides: some View {
        HStack(spacing: 14) {
            side(.a, subject)
            side(.b, partner)
        }
        .glassCard()
    }

    private func side(_ s: PairSide, _ chart: SavedChart) -> some View {
        HStack(spacing: 8) {
            SideBadge(side: s)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: chart.name).font(.subheadline.weight(.semibold))
                if !chart.isTimeKnown {
                    Text("Birth time unknown")
                        .font(.caption2)
                        .foregroundStyle(NebulaPalette.retrograde)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var synastry: some View {
        VStack(spacing: 16) {
            MomentReadout(moment: SkyMoment(positions: subject.positions,
                                            aspects: subject.aspects,
                                            houses: subject.houses(system: houseSystem),
                                            houseFallback: nil,
                                            outerPositions: partner.positions,
                                            crossAspects: subject.synastry(with: partner)),
                          lens: $lens,
                          houseSystem: $houseSystem,
                          heading: "Synastry")
            CrossAspectList(chart: subject,
                            cross: subject.synastry(with: partner),
                            partner: partner)
        }
    }

    @ViewBuilder
    private var compositeView: some View {
        let c = composite
        VStack(spacing: 16) {
            // The midpoint method is named on the chart, not buried in a help screen: a composite
            // built from midpoints is a different object from one built from a time-space
            // reference, and a practitioner needs to know which they are reading.
            Text("Midpoint composite")
                .font(.caption)
                .foregroundStyle(NebulaPalette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            MomentReadout(moment: SkyMoment(positions: c.positions,
                                            aspects: Aspects.detect(in: c.positions, orbFactor: 1.0),
                                            houses: nil,
                                            houseFallback: nil,
                                            outerPositions: nil,
                                            crossAspects: []),
                          lens: $lens,
                          houseSystem: $houseSystem,
                          heading: "Composite")
                .accessibilityIdentifier(NebulaPractitioner.A11y.pairingComposite)

            // Composite houses need both birth times. The planets are exact midpoints regardless,
            // so they compute — it is only the angles that are unavailable, and saying which is
            // the difference between a limit and a failure.
            if c.ascendant == nil || c.midheaven == nil {
                HonestStateCard(
                    title: L.string("No composite houses", locale: locale),
                    explanation: L.string(
                        "A composite Ascendant is the midpoint of two Ascendants, so it needs a birth time on both sides. The planets above are exact.",
                        locale: locale),
                    fixLabel: L.string("Add the missing birth time", locale: locale))
            }

            if !c.ambiguousBodies.isEmpty {
                HonestStateCard(
                    title: L.string("Opposed pairs", locale: locale),
                    explanation: String(
                        format: L.string("%@ sit exactly opposite, so their midpoint could be either of two points.", locale: locale),
                        c.ambiguousBodies.map(\.glyph).joined(separator: " ")))
            }
        }
    }
}
