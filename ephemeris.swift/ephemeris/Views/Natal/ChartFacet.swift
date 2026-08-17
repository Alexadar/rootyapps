import SwiftUI

/// The four readings of a saved chart.
///
/// This replaces the old two-way `Natal | Transits` control on the chart detail. That control was
/// already the bi-wheel switch in disguise — "Transits" meant "put a second ring outside" — so it
/// becomes the *source* of that outer ring (`NebulaPractitioner.BiWheelSource`) and this enum takes
/// its place one level up.
///
/// Four and not eight: the seven practitioner features do not each get a destination. Progressions,
/// returns and synastry are all "a second ring over the natal wheel", so they share `biwheel` and
/// differ only in what feeds it; dignities, shape, balances and midpoints are all "what this chart
/// is made of", so they share `analysis` as cards. Only returns needs its own facet, because
/// choosing *which* return is a list, not a ring.
///
/// **This is not a navigation section.** `ChartSection` still has three cases and the fourth seat
/// stays empty; `LegacyTab.destination(for:)` and `EPHEMERIS_TAB` 0–5 are untouched, so every
/// existing deep link and store screenshot still lands where it did.
enum ChartFacet: String, CaseIterable, Identifiable, Sendable {
    case wheel, biwheel, analysis, returns

    var id: String { rawValue }

    /// Short, because four of these share a segmented control and German and Polish both run long.
    /// The chart's name carries the context in the navigation title above.
    var title: LocalizedStringKey {
        switch self {
        case .wheel:    "Wheel"
        case .biwheel:  "Bi-wheel"
        case .analysis: "Analysis"
        case .returns:  "Returns"
        }
    }

    var icon: String {
        switch self {
        case .wheel:    "circle.hexagongrid"
        case .biwheel:  "circle.circle"
        case .analysis: "chart.pie"
        case .returns:  "arrow.uturn.backward.circle"
        }
    }
}
