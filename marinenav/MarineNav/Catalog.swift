import SwiftUI

/// The app's tool catalog. Ordered by the product's priority: this is a tides app
/// with navigation support, not five equal peers.
enum Tool: String, CaseIterable, Identifiable {
    case tides
    case currents
    case declination
    case distanceBearing
    case sightReduction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tides:           return "Tides"
        case .currents:        return "Currents"
        case .declination:     return "Declination"
        case .distanceBearing: return "Distance & Bearing"
        case .sightReduction:  return "Sight Reduction"
        }
    }

    var subtitle: String {
        switch self {
        case .tides:           return "Heights, highs and lows"
        case .currents:        return "Slack, flood and ebb"
        case .declination:     return "True vs magnetic"
        case .distanceBearing: return "Great-circle passage"
        case .sightReduction:  return "Celestial line of position"
        }
    }

    var symbol: String {
        switch self {
        case .tides:           return "water.waves"
        case .currents:        return "arrow.left.arrow.right"
        case .declination:     return "location.north.line"
        case .distanceBearing: return "point.topleft.down.to.point.bottomright.curvepath"
        case .sightReduction:  return "sun.horizon"
        }
    }

    /// Which Kit backs this tool. Surfaced in the UI on purpose — the moat is
    /// validated math, so the provenance is part of the product, not a footnote.
    var kit: String {
        switch self {
        case .tides, .currents: return "TidesKit"
        case .declination:      return "GeomagKit"
        case .distanceBearing:  return "GeodesyKit"
        case .sightReduction:   return "CelestialNavKit"
        }
    }

    /// The external authority every number in this tool is tested against.
    var oracle: String {
        switch self {
        case .tides:
            return "Schureman (USC&GS Sp. Pub. 98) + NOAA CO-OPS published predictions"
        case .currents:
            return "NOAA CO-OPS published current predictions"
        case .declination:
            return "NOAA/NCEI & BGS World Magnetic Model 2025"
        case .distanceBearing:
            return "Vincenty (1975) + Karney GeodTest"
        case .sightReduction:
            return "Bowditch, American Practical Navigator (NGA Pub. 9)"
        }
    }

    @ViewBuilder var destination: some View {
        switch self {
        case .tides:           TidesToolView()
        case .currents:        CurrentsToolView()
        case .declination:     DeclinationToolView()
        case .distanceBearing: DistanceBearingToolView()
        case .sightReduction:  SightReductionToolView()
        }
    }
}
