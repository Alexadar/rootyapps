import SwiftUI

enum ToolSection: String, CaseIterable, Identifiable {
    case framing = "Framing", concrete = "Concrete", takeoff = "Takeoff",
         materials = "Materials", convert = "Convert"
    var id: String { rawValue }
}

enum Tool: String, CaseIterable, Identifiable, Hashable {
    case rafter, stairs, pitch                        // Framing
    case concrete, footing, rebar, aggregate, pavers  // Concrete
    case area, volume                                 // Takeoff
    case roofing, estimate, miter, lumber, mortar     // Materials
    case units                                        // Convert

    var id: String { rawValue }

    var section: ToolSection {
        switch self {
        case .rafter, .stairs, .pitch: return .framing
        case .concrete, .footing, .rebar, .aggregate, .pavers: return .concrete
        case .area, .volume: return .takeoff
        case .roofing, .estimate, .miter, .lumber, .mortar: return .materials
        case .units: return .convert
        }
    }

    var title: String {
        switch self {
        case .rafter: return "Rafter"; case .stairs: return "Stairs"; case .pitch: return "Right Angle"
        case .concrete: return "Concrete"; case .footing: return "Footing"; case .rebar: return "Rebar"; case .aggregate: return "Aggregate"; case .pavers: return "Pavers"
        case .area: return "Area"; case .volume: return "Volume"
        case .roofing: return "Roofing"; case .estimate: return "Estimate"; case .miter: return "Miter"; case .lumber: return "Lumber"; case .mortar: return "Mortar"
        case .units: return "Convert"
        }
    }

    var subtitle: String {
        switch self {
        case .rafter: return "Common · hip · valley · jack"
        case .stairs: return "Risers, treads, stringer, code"
        case .pitch: return "Rise · run · diagonal · pitch"
        case .concrete: return "Yards & bags — slab, column"
        case .footing: return "Strip · pad · wall — yd³ & rebar"
        case .rebar: return "ASTM sizes, weight, slab mat"
        case .aggregate: return "Gravel & base — yards to tons"
        case .pavers: return "Pavers & retaining-wall block"
        case .area: return "Rect · triangle · circle"
        case .volume: return "Box · cylinder — yd³"
        case .roofing: return "Squares & pitch multiplier"
        case .estimate: return "Drywall · paint · block"
        case .miter: return "Compound crown angles"
        case .lumber: return "Board feet"
        case .mortar: return "Mortar bags — block & brick"
        case .units: return "ft-in ↔ decimal ↔ metric"
        }
    }

    var symbol: String {
        switch self {
        case .rafter: return "triangle"; case .stairs: return "stairs"; case .pitch: return "angle"
        case .concrete: return "cube.transparent"; case .footing: return "rectangle.compress.vertical"; case .rebar: return "line.3.horizontal"; case .aggregate: return "circle.hexagongrid.fill"; case .pavers: return "square.grid.3x3.fill"
        case .area: return "square.dashed"; case .volume: return "shippingbox"
        case .roofing: return "house"; case .estimate: return "square.grid.3x3"; case .miter: return "arrowtriangle.left.and.line.vertical.and.arrowtriangle.right"; case .lumber: return "ruler"; case .mortar: return "square.grid.3x3.middle.filled"
        case .units: return "arrow.left.arrow.right"
        }
    }

    var sample: String {
        switch self {
        case .rafter: return "13.42\"/ft"; case .stairs: return "14 risers"; case .pitch: return "3-4-5"
        case .concrete: return "45 bags/yd³"; case .footing: return "3.29 yd³"; case .rebar: return "#4 0.668/ft"; case .aggregate: return "1.35 t/yd³"; case .pavers: return "4.5 /ft²"
        case .area: return "π r²"; case .volume: return "27 ft³"
        case .roofing: return "6/12 →1.118"; case .estimate: return "35 sheets"; case .miter: return "35.3°"; case .lumber: return "10 bf"; case .mortar: return "13 blk/bag"
        case .units: return "1 ft = 0.3048 m"
        }
    }

    static func tools(in section: ToolSection) -> [Tool] { allCases.filter { $0.section == section } }
}
