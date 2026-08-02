import SwiftUI

// Wayfinding data model — the catalog of calculators and their section membership.
// Mirrors the shape the app's real model should expose (rawValue ids, section, title,
// subtitle, SF Symbol). Adapt names to the shipping `Calculator`/tool enum; the design
// system only needs `.rawValue`, `.section`, `.title`, `.subtitle`, `.symbol`.

enum Calculator: String, CaseIterable, Identifiable, Hashable {
    // Wind
    case windTriangle, crosswind
    // Airspeed
    case trueAirspeed, machNumber
    // Altitude
    case densityAltitude, pressureAltitude
    // Nav
    case navLog, magVariation
    // Fuel
    case fuelBurn, fuelEndurance
    // Climb / Descent
    case climbGradient, descentPlanning
    // Weight & Balance
    case weightBalance
    // Convert
    case unitConvert

    var id: String { rawValue }

    var section: CalcSection {
        switch self {
        case .windTriangle, .crosswind:          return .wind
        case .trueAirspeed, .machNumber:         return .airspeed
        case .densityAltitude, .pressureAltitude:return .altitude
        case .navLog, .magVariation:             return .nav
        case .fuelBurn, .fuelEndurance:          return .fuel
        case .climbGradient, .descentPlanning:   return .climb
        case .weightBalance:                     return .weightBal
        case .unitConvert:                       return .convert
        }
    }

    var title: String {
        switch self {
        case .windTriangle:    return "Wind Triangle"
        case .crosswind:       return "Crosswind"
        case .trueAirspeed:    return "True Airspeed"
        case .machNumber:      return "Mach Number"
        case .densityAltitude: return "Density Altitude"
        case .pressureAltitude:return "Pressure Altitude"
        case .navLog:          return "Nav Log"
        case .magVariation:    return "Mag Variation"
        case .fuelBurn:        return "Fuel / Time"
        case .fuelEndurance:   return "Endurance"
        case .climbGradient:   return "Climb Gradient"
        case .descentPlanning: return "Descent Planning"
        case .weightBalance:   return "Weight & Balance"
        case .unitConvert:     return "Convert"
        }
    }

    var subtitle: String {
        switch self {
        case .windTriangle:    return "Heading · GS · WCA"
        case .crosswind:       return "Head / cross component"
        case .trueAirspeed:    return "CAS → TAS"
        case .machNumber:      return "TAS → Mach"
        case .densityAltitude: return "OAT · PA → DA"
        case .pressureAltitude:return "Altimeter → PA"
        case .navLog:          return "Legs · ETE · ETA"
        case .magVariation:    return "True ↔ magnetic"
        case .fuelBurn:        return "Burn · reserve"
        case .fuelEndurance:   return "Time remaining"
        case .climbGradient:   return "ft/NM · %"
        case .descentPlanning: return "TOD · rate"
        case .weightBalance:   return "CG · envelope"
        case .unitConvert:     return "kt · mph · km/h · …"
        }
    }

    /// SF Symbol for the tile / row / sidebar icon.
    var symbol: String {
        switch self {
        case .windTriangle:    return "wind"
        case .crosswind:       return "arrow.left.arrow.right"
        case .trueAirspeed:    return "gauge.with.dots.needle.67percent"
        case .machNumber:      return "speedometer"
        case .densityAltitude: return "mountain.2"
        case .pressureAltitude:return "barometer"
        case .navLog:          return "point.topleft.down.to.point.bottomright.curvepath"
        case .magVariation:    return "location.north.line"
        case .fuelBurn:        return "fuelpump"
        case .fuelEndurance:   return "clock"
        case .climbGradient:   return "chart.line.uptrend.xyaxis"
        case .descentPlanning: return "chart.line.downtrend.xyaxis"
        case .weightBalance:   return "scalemass"
        case .unitConvert:     return "arrow.triangle.swap"
        }
    }

    static func calculators(in section: CalcSection) -> [Calculator] {
        allCases.filter { $0.section == section }
    }
}
