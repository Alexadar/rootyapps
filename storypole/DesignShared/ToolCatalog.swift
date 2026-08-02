import SwiftUI

/// The 16 shipping calculators, and nothing else.
///
/// This list is the contract established by the oracle gate
/// (`docs/storypole_oracle_gate_2026-07-29.md`). **Design must not invent a tool that is not here,
/// and no tool may be added without passing the four-step gate in `HANDOFF_storypole.md` §4.**
///
/// Cut list with kerf was researched and dropped: no published authority, and the phrase
/// `cut list optimizer` already autocompletes to five named apps.
public enum ToolSection: String, CaseIterable, Identifiable, Sendable {
    case tape      = "Tape"
    case layout    = "Layout"
    case takeoff   = "Takeoff"
    case roof      = "Roof"
    case geometry  = "Geometry"
    case lumber    = "Lumber"
    case gauge     = "Gauge"

    public var id: String { rawValue }

    /// Each section owns a hue, now with a dark-mode value.
    /// **This property is the only thing the design layer changed in this file.**
    public var accent: Color {
        switch self {
        case .tape:     return SP.accent
        case .layout:   return Color(light: 0x1A6A5E, dark: 0x3FB3A1)
        case .takeoff:  return Color(light: 0x35538F, dark: 0x7C9BE0)
        case .roof:     return Color(light: 0x8A5A2B, dark: 0xD1974F)
        case .geometry: return Color(light: 0x63489A, dark: 0xAE93E8)
        case .lumber:   return Color(light: 0x53712B, dark: 0x9DBE5A)
        case .gauge:    return Color(light: 0x8A2E4E, dark: 0xE0709A)
        }
    }
}

public enum Tool: String, CaseIterable, Identifiable, Hashable, Sendable {
    // Tape — the core engine
    case tapeCalc, convert, fraction
    // Layout — the differentiator
    case equalSpacing, onCenter
    // Takeoff
    case area, volume, cubicYards
    // Roof
    case roofPitch, rafter
    // Geometry
    case diagonal, miter, circle
    // Lumber
    case boardFeet, dressedSize
    // Gauge — dimension only, never ampacity
    case wireGauge

    public var id: String { rawValue }

    public var section: ToolSection {
        switch self {
        case .tapeCalc, .convert, .fraction:        return .tape
        case .equalSpacing, .onCenter:              return .layout
        case .area, .volume, .cubicYards:           return .takeoff
        case .roofPitch, .rafter:                   return .roof
        case .diagonal, .miter, .circle:            return .geometry
        case .boardFeet, .dressedSize:              return .lumber
        case .wireGauge:                            return .gauge
        }
    }

    public var title: LocalizedStringKey {
        switch self {
        case .tapeCalc:     return "Tape Calculator"
        case .convert:      return "Convert"
        case .fraction:     return "Fraction Round"
        case .equalSpacing: return "Equal Spacing"
        case .onCenter:     return "On Center"
        case .area:         return "Area"
        case .volume:       return "Volume"
        case .cubicYards:   return "Cubic Yards"
        case .roofPitch:    return "Roof Pitch"
        case .rafter:       return "Rafter"
        case .diagonal:     return "Square Up"
        case .miter:        return "Miter & Bevel"
        case .circle:       return "Circle & Pipe Wrap"
        case .boardFeet:    return "Board Feet"
        case .dressedSize:  return "Nominal vs Dressed"
        case .wireGauge:    return "Wire Gauge"
        }
    }

    public var subtitle: LocalizedStringKey {
        switch self {
        case .tapeCalc:     return "Add, subtract, multiply feet-inch-fractions"
        case .convert:      return "Inch, foot, yard, mm, cm, m"
        case .fraction:     return "Round to 1/2 … 1/64"
        case .equalSpacing: return "Divide a span, get every mark"
        case .onCenter:     return "16\", 19.2\", 24\" and the odd last bay"
        case .area:         return "Square footage from feet and inches"
        case .volume:       return "Box, cylinder, cone, sphere"
        case .cubicYards:   return "Concrete takeoff"
        case .roofPitch:    return "x-in-12, degrees, percent"
        case .rafter:       return "Common, hip, valley, jack"
        case .diagonal:     return "3-4-5 and the true diagonal"
        case .miter:        return "Any corner, plus crown"
        case .circle:       return "Circumference, arc, arch"
        case .boardFeet:    return "Nominal board measure"
        case .dressedSize:  return "Why a 2×4 is 1½\" × 3½\""
        case .wireGauge:    return "AWG diameter"
        }
    }

    public var symbol: String {
        switch self {
        case .tapeCalc:     return "ruler"
        case .convert:      return "arrow.left.arrow.right"
        case .fraction:     return "textformat.superscript"
        case .equalSpacing: return "distribute.horizontal.center"
        case .onCenter:     return "chart.bar.doc.horizontal"
        case .area:         return "square.dashed"
        case .volume:       return "cube"
        case .cubicYards:   return "shippingbox"
        case .roofPitch:    return "triangle"
        case .rafter:       return "house"
        case .diagonal:     return "square.righthalf.filled"
        case .miter:        return "angle"
        case .circle:       return "circle.dashed"
        case .boardFeet:    return "rectangle.stack"
        case .dressedSize:  return "list.bullet.rectangle"
        case .wireGauge:    return "cable.connector"
        }
    }

    /// A representative value shown on the catalog tile, so a tool is recognisable before opening.
    public var sample: String {
        switch self {
        case .tapeCalc:     return "8' 10-1/4\""
        case .convert:      return "25.4 mm"
        case .fraction:     return "1/16"
        case .equalSpacing: return "7 marks"
        case .onCenter:     return "16\" o.c."
        case .area:         return "152 sq ft"
        case .volume:       return "26.7 cu ft"
        case .cubicYards:   return "1.23 yd³"
        case .roofPitch:    return "6/12"
        case .rafter:       return "13.42\"/ft"
        case .diagonal:     return "3-4-5"
        case .miter:        return "45°"
        case .circle:       return "πd"
        case .boardFeet:    return "5⅓ BF"
        case .dressedSize:  return "1½ × 3½"
        case .wireGauge:    return "12 AWG"
        }
    }

    /// Tools that ship on the wrist. Seven of sixteen: one or two inputs, one number out.
    /// Layout marks, area/volume, rafter and miter are cut — multi-input, or the answer is a list,
    /// and a 41 mm screen is the wrong place for either.
    public var onWatch: Bool {
        switch self {
        case .tapeCalc, .convert, .roofPitch, .boardFeet, .diagonal, .circle, .wireGauge: return true
        default: return false
        }
    }

    public static func tools(in section: ToolSection) -> [Tool] {
        allCases.filter { $0.section == section }
    }

    public static var watchTools: [Tool] { allCases.filter(\.onWatch) }
}
