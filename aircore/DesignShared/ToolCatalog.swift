import SwiftUI

public enum ToolSection: String, CaseIterable, Identifiable, Sendable {
    case air = "Air"
    case distribution = "Distribution"
    case water = "Water"

    public var id: String { rawValue }
}

/// Every tool in the app. One record, many tools — not four apps.
///
/// A closed enum, so a tool cannot exist without a title, a section, a Kit behind it and a screen.
/// Adding a case makes the compiler ask for all four.
///
/// ## What is deliberately absent
///
/// There is no fitting library, no equivalent length and no load calculation: that data is
/// licensed. There is no flue, vent, combustion-air or gas-pipe tool: that is life-safety
/// territory where the failure mode is carbon monoxide. Neither absence is a gap to be filled
/// later — the app is defined as much by these as by what it does.
public enum Tool: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case psychrometrics
    case airsideHeat
    case mixing
    case duct
    case fan
    case pipe

    public var id: String { rawValue }

    public var section: ToolSection {
        switch self {
        case .psychrometrics, .airsideHeat, .mixing: return .air
        case .duct, .fan:                            return .distribution
        case .pipe:                                  return .water
        }
    }

    public var title: LocalizedStringKey {
        switch self {
        case .psychrometrics: return "Psychrometrics"
        case .airsideHeat:    return "Air-side heat"
        case .mixing:         return "Air mixing"
        case .duct:           return "Duct sizing"
        case .fan:            return "Fan laws"
        case .pipe:           return "Pipe sizing"
        }
    }

    /// The plain-text title, for accessibility labels and export headers where a
    /// `LocalizedStringKey` cannot go.
    public var plainTitle: String {
        switch self {
        case .psychrometrics: return "Psychrometrics"
        case .airsideHeat:    return "Air-side heat"
        case .mixing:         return "Air mixing"
        case .duct:           return "Duct sizing"
        case .fan:            return "Fan laws"
        case .pipe:           return "Pipe sizing"
        }
    }

    public var subtitle: LocalizedStringKey {
        switch self {
        case .psychrometrics: return "Any two knowns, the whole state"
        case .airsideHeat:    return "Sensible · latent · total"
        case .mixing:         return "Two airstreams, one state"
        case .duct:           return "Straight duct from friction"
        case .fan:            return "Affinity laws & density"
        case .pipe:           return "Water, head loss & velocity"
        }
    }

    public var symbol: String {
        switch self {
        case .psychrometrics: return "chart.xyaxis.line"
        case .airsideHeat:    return "flame"
        case .mixing:         return "arrow.triangle.merge"
        case .duct:           return "rectangle.split.3x1"
        case .fan:            return "fanblades"
        case .pipe:           return "drop"
        }
    }

    public static func tools(in section: ToolSection) -> [Tool] {
        allCases.filter { $0.section == section }
    }
}
