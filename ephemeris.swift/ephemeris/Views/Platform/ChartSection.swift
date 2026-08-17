import SwiftUI
import EphemerisKit

/// The three top-level categories.
///
/// Six flat sections became three because iOS folds anything past the fifth tab into **More**, and
/// that is where Natal — the reason a practitioner buys this class of app — had ended up. The first
/// four were never peers anyway: Chart, Positions and Aspects are three readings of one instant, so
/// they are lenses inside Sky rather than destinations beside it.
///
/// A fourth seat is left free on purpose. Returns, progressions, synastry, composite, dignities,
/// analysis and astrocartography all exist in the Kit with no surface yet, and they are per-chart —
/// so they belong inside Charts rather than as new categories. The seat is headroom, not a plan.
enum ChartSection: Int, CaseIterable, Identifiable {
    case sky, charts, cycles

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .sky:    "Sky"
        case .charts: "Charts"
        case .cycles: "Cycles"
        }
    }

    var icon: String {
        switch self {
        case .sky:    "circle.hexagongrid"
        case .charts: "person.crop.circle"
        case .cycles: "arrow.triangle.2.circlepath"
        }
    }
}

/// Which reading a category is showing.
enum CyclesLens: String, CaseIterable, Identifiable {
    case timeline, synodic
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .timeline: "Events"
        case .synodic:  "Cycle"
        }
    }
    var icon: String {
        switch self {
        case .timeline: "calendar"
        case .synodic:  "arrow.triangle.2.circlepath"
        }
    }
}

/// Where a legacy `EPHEMERIS_TAB` index lands.
///
/// **This is a compatibility contract, not a convenience.** Every store screenshot and preview is
/// captured by setting this variable, and three UI tests assert each index reaches a screen-unique
/// marker. Regrouping the navigation without this mapping would silently point the capture pipeline
/// at the wrong screens — which is precisely how an iPad screenshot of the wrong tab once shipped
/// with a confident caption.
///
/// | index | was | now |
/// |---|---|---|
/// | 0 | Chart | Sky · Wheel |
/// | 1 | Positions | Sky · Table |
/// | 2 | Aspects | Sky · Aspects |
/// | 3 | Cycle | Cycles · Synodic |
/// | 4 | Events | Cycles · Timeline |
/// | 5 | Natal | Charts |
enum LegacyTab {
    struct Destination {
        var section: ChartSection
        var moment: MomentLens?
        var cycles: CyclesLens?
    }

    static func destination(for index: Int) -> Destination {
        switch index {
        case 0:  Destination(section: .sky, moment: .wheel, cycles: nil)
        case 1:  Destination(section: .sky, moment: .table, cycles: nil)
        case 2:  Destination(section: .sky, moment: .aspects, cycles: nil)
        case 3:  Destination(section: .cycles, moment: nil, cycles: .synodic)
        case 4:  Destination(section: .cycles, moment: nil, cycles: .timeline)
        case 5:  Destination(section: .charts, moment: nil, cycles: nil)
        default: Destination(section: .sky, moment: .wheel, cycles: nil)
        }
    }
}
