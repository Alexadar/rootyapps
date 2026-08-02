import Foundation

/// A calculator tool. The raw value doubles as the deep-link token and favourite id.
/// Groups/accents come from the design system's `CalcGroup` (see TCColors.swift).
enum Tool: String, CaseIterable, Identifiable, Hashable {
    case wind
    case airspeed
    case altitude
    case nav
    case fuel
    case climb
    case wb
    case convert
    case timer

    var id: String { rawValue }

    var group: CalcGroup {
        switch self {
        case .wind, .nav, .fuel, .climb: return .planning
        case .airspeed, .altitude, .wb:  return .performance
        case .convert, .timer:           return .tools
        }
    }

    var title: String {
        switch self {
        case .wind:     return "Wind Triangle"
        case .airspeed: return "True Airspeed"
        case .altitude: return "Altitude"
        case .nav:      return "Nav Log"
        case .fuel:     return "Fuel"
        case .climb:    return "Climb & Descent"
        case .wb:       return "Weight & Balance"
        case .convert:  return "Convert"
        case .timer:    return "Clock & Timer"
        }
    }

    var subtitle: String {
        switch self {
        case .wind:     return "Heading, GS & crosswind"
        case .airspeed: return "TAS & Mach from CAS"
        case .altitude: return "Density, pressure, true"
        case .nav:      return "Time · speed · distance"
        case .fuel:     return "Burn, endurance, range"
        case .climb:    return "Rates, TOD, glide"
        case .wb:       return "CG & envelope check"
        case .convert:  return "Aviation unit conversions"
        case .timer:    return "Zulu, local & count-down"
        }
    }

    var symbol: String {
        switch self {
        case .wind:     return "location.north.line.fill"
        case .airspeed: return "speedometer"
        case .altitude: return "mountain.2.fill"
        case .nav:      return "map.fill"
        case .fuel:     return "fuelpump.fill"
        case .climb:    return "airplane.departure"
        case .wb:       return "scalemass.fill"
        case .convert:  return "arrow.left.arrow.right"
        case .timer:    return "clock.fill"
        }
    }

    static func tools(in group: CalcGroup) -> [Tool] {
        allCases.filter { $0.group == group }
    }
}
