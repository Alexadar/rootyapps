import SwiftUI

/// The panel registry — wayfinding data only. Each panel of the snapshot belongs to one
/// side of the matchup (Sun acting / Earth responding / the solar-wind link), and the
/// side owns the panel's accent. Presentation only: the set of panels and their metrics
/// is defined by `SpaceWeatherSnapshot` and must not change here.
enum SWPanel: String, CaseIterable, Identifiable {
    case scales   = "NOAA Space Weather Scales"
    case kp       = "Planetary Kp"
    case hpo      = "Hp30 · High-Cadence Geomagnetic Index"
    case wind     = "Solar Wind"
    case flare    = "Solar Flares & X-ray Flux"
    case aurora   = "Aurora"
    case solar    = "Solar Activity"

    var id: String { rawValue }

    /// Which side of the matchup the panel reports.
    var side: SWSide {
        switch self {
        case .flare, .solar:          return .solar
        case .kp, .hpo, .aurora:      return .terra
        case .wind:                   return .link
        case .scales:                 return .terra   // the scoreline — Earth's response
        }
    }

    /// SF Symbol glyph for grids, sidebars, and widgets.
    var glyph: String {
        switch self {
        case .scales: return "gauge.with.dots.needle.33percent"
        case .kp:     return "waveform.path.ecg"
        case .hpo:    return "bolt.horizontal"
        case .wind:   return "wind"
        case .flare:  return "sun.max"
        case .aurora: return "sparkles"
        case .solar:  return "circle.grid.cross"
        }
    }

    /// The cited source, verbatim — the trust moat.
    var source: String {
        switch self {
        case .scales: return "NOAA SWPC"
        case .kp:     return "NOAA SWPC"
        case .hpo:    return "GFZ Potsdam · Hpo"
        case .wind:   return "NOAA SWPC · DSCOVR/ACE"
        case .flare:  return "NOAA SWPC · GOES"
        case .aurora: return "NOAA SWPC · OVATION"
        case .solar:  return "NOAA SWPC · Wolf R"
        }
    }
}
