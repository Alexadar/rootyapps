import SwiftUI
import EphemerisKit

/// One moment, read four ways — built once, fed by either the live sky or a saved birth chart.
///
/// ## Why this exists
///
/// Chart, Positions and Aspects used to be three top-level tabs, which read as three destinations
/// when they are really three presentations of the same instant. Worse, once saved charts arrived
/// the same three views were needed again for a frozen moment — and building them twice is how two
/// copies of one thing start disagreeing, exactly as the angle maths did before `ChartGeometry`.
///
/// So the lens is a control, not a destination, and the data is a parameter. `SkyMoment` is the seam:
/// the live view model fills it from `ChartViewModel`, the natal view fills it from a `SavedChart`,
/// and neither knows about the other.
struct SkyMoment {
    var positions: [BodyPosition]
    var aspects: [DetectedAspect]
    var houses: HouseCusps?
    var houseFallback: HouseSystem?
    /// Transiting bodies for the bi-wheel; nil draws a single wheel.
    var outerPositions: [BodyPosition]?
    var crossAspects: [CrossAspect] = []
}

/// Which way the moment is being read.
enum MomentLens: String, CaseIterable, Identifiable {
    case wheel, table, aspects, houses
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .wheel:   "Chart"
        case .table:   "Positions"
        case .aspects: "Aspects"
        case .houses:  "Houses"
        }
    }

    /// Deliberately the same keys the old tabs used, so nothing needed retranslating and the labels
    /// a user already knows did not move.
    var icon: String {
        switch self {
        case .wheel:   "circle.hexagongrid"
        case .table:   "list.star"
        case .aspects: "point.3.connected.trianglepath.dotted"
        case .houses:  "house"
        }
    }
}

struct MomentReadout: View {
    let moment: SkyMoment
    @Binding var lens: MomentLens
    @Binding var houseSystem: HouseSystem

    /// A heading above the lens control, when the context needs naming.
    ///
    /// **Segments stay short; the heading carries the long form.** "Natal chart" in a four-segment
    /// control truncates badly once translated — German is *Geburtshoroskop*, Polish *Horoskop
    /// urodzeniowy* — and squeezes the other three. Here it has a full line and can wrap.
    var heading: LocalizedStringKey? = nil

    private var wheel: ChartWheel {
        ChartWheel(positions: moment.positions,
                   aspects: moment.aspects,
                   houses: moment.houses,
                   outerPositions: moment.outerPositions,
                   crossAspects: moment.crossAspects)
    }

    var body: some View {
        VStack(spacing: 16) {
            if let heading {
                Text(heading)
                    .font(.headline)
                    // Wraps rather than truncating — the long localized forms need the room.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("heading.readout")
            }

            Picker(heading ?? "Chart", selection: $lens) {
                ForEach(MomentLens.allCases) { l in
                    Label(l.title, systemImage: l.icon).tag(l)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("input.lens")

            switch lens {
            case .wheel:
                // Two columns where the window can hold them. The wheel is square, so a single
                // column either wastes the right half of a wide window or inflates the wheel to
                // fill it — and side by side is how the practitioner tools this competes with are
                // laid out. `ViewThatFits` rather than a GeometryReader: it picks the wide
                // arrangement only when it genuinely fits, with no size plumbing.
                //
                // Living here rather than in the macOS root means iPad gets it too, instead of the
                // Mac having a private copy that iPad never receives.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        wheel.frame(minWidth: 380, maxWidth: 560)
                        TightestAspects(aspects: moment.aspects).frame(minWidth: 340)
                    }
                    VStack(spacing: 16) {
                        wheel
                        TightestAspects(aspects: moment.aspects)
                    }
                }
            case .table:
                PositionsTable(positions: moment.positions)
            case .aspects:
                AspectsList(aspects: moment.aspects)
            case .houses:
                HousesCard(houses: moment.houses,
                           fallback: moment.houseFallback,
                           system: $houseSystem)
            }
        }
    }
}
