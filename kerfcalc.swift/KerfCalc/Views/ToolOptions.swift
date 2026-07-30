import Foundation
import GeometryKit
import ConcreteKit
import FramingKit

/// Segmented-picker option tables for the tools whose mode switch was still inline in the view.
///
/// Same rationale as `PipeOptions` and `ToolHeroes`: the index → value mapping is the part that fails
/// silently. A wrong row feeds an *otherwise correct* Kit the wrong input, and the screen looks
/// perfectly normal — every number rendered, nothing crashed, just wrong. Nothing but a test on the
/// mapping itself can catch that, and a mapping buried in a `switch` inside a `body` cannot be tested.
///
/// Two concrete hazards these remove:
///
/// 1. **`allCases[index]` traps on an out-of-range index.** Four screens did that (`BarSize.allCases[barIdx]`,
///    `AggregateMaterial.allCases[matIdx]`). The picker keeps the index in range today, so it never
///    crashed — but the invariant lived nowhere, and `KERFCALC_SCREEN` can now seed the index from the
///    environment. The accessors below clamp instead.
/// 2. **A magic array indexed by a picker** — `[0.60, 0.45, 0.30][bagIdx]` for concrete bag yield, with
///    the bag sizes named only in the picker's own `titles`. Now the titles and the yields sit together
///    and a test asserts they are the same length.
///
/// Each type owns the `titles` its `SubScreenPicker` renders, so the control and the mapping cannot
/// drift apart. See `kerfcalcTests/ToolOptionsTests.swift`.

// MARK: - Takeoff

/// Area tool — Rectangle (0) / Triangle (1) / Circle (2).
enum AreaShapeChoice {
    static let titles = ["Rectangle", "Triangle", "Circle"]

    /// `a` is length/base/radius, `b` is width/height (unused for a circle).
    static func areaFt2(index: Int, a: Double, b: Double) -> Double {
        switch index {
        case 0:  return Area.rectangle(length: a, width: b)
        case 1:  return Area.triangle(base: a, height: b)
        default: return Area.circle(radius: a)
        }
    }
}

/// Volume tool — Box (0) / Cylinder (1).
enum VolumeShapeChoice {
    static let titles = ["Box", "Cylinder"]

    /// A cylinder takes its diameter from `a` and its height from `c` — NOT `b`, which the box uses as
    /// width. Getting that wrong silently returns a plausible volume, which is why it is pinned here.
    static func volumeFt3(index: Int, a: Double, b: Double, c: Double) -> Double {
        index == 0 ? Volume.box(length: a, width: b, height: c)
                   : Volume.cylinder(diameter: a, height: c)
    }
}

/// Concrete tool — Slab / Footing (0) / Column / Hole (1).
enum ConcreteFormChoice {
    static let titles = ["Slab / Footing", "Column / Hole"]

    static func cubicFeet(index: Int, lenFt: Double, widFt: Double, thickIn: Double,
                          diaIn: Double, depthIn: Double) -> Double {
        index == 0 ? Concrete.slabCubicFeet(lengthFt: lenFt, widthFt: widFt, thicknessInches: thickIn)
                   : Concrete.columnCubicFeet(diameterInches: diaIn, heightInches: depthIn)
    }
}

/// Concrete bag size — 80 lb (0) / 60 lb (1) / 40 lb (2), by yield in ft³ per bag.
enum ConcreteBagChoice {
    static let titles = ["80 lb", "60 lb", "40 lb"]
    /// Yield per bag, ft³. Industry nominal: an 80 lb bag makes 0.60 ft³.
    static let yields: [Double] = [0.60, 0.45, 0.30]

    static func yieldFt3(index: Int) -> Double {
        yields.indices.contains(index) ? yields[index] : yields[0]
    }
}

// MARK: - Concrete section

/// Footing tool — Strip (0) / Pad (1) / Wall (2).
enum FootingKindChoice {
    static let titles = ["Strip", "Pad", "Wall"]

    static func cubicFeet(index: Int,
                          lenFt: Double, widIn: Double, depIn: Double,
                          padL: Double, padW: Double, padD: Double,
                          wallLen: Double, wallH: Double, wallT: Double) -> Double {
        switch index {
        case 0:  return Footing.continuousCubicFeet(lengthFt: lenFt, widthIn: widIn, depthIn: depIn)
        case 1:  return Footing.padCubicFeet(lengthIn: padL, widthIn: padW, depthIn: padD)
        default: return Footing.wallCubicFeet(lengthFt: wallLen, heightFt: wallH, thicknessIn: wallT)
        }
    }

    /// Rebar run length. A PAD has no continuous run, so this is 0 for it — not the strip's length.
    static func runFeet(index: Int, lenFt: Double, wallLen: Double) -> Double {
        switch index {
        case 0:  return lenFt
        case 2:  return wallLen
        default: return 0
        }
    }
}

/// Rebar bar size, chosen by picker row. Clamped: `BarSize.allCases[i]` traps out of range.
enum BarSizeChoice {
    static var titles: [String] { BarSize.allCases.map(\.label) }

    static func size(index: Int) -> BarSize {
        let all = BarSize.allCases
        return all.indices.contains(index) ? all[index] : all[0]
    }
}

/// Aggregate material, chosen by picker row. Clamped for the same reason.
enum AggregateMaterialChoice {
    /// The picker shows only the first word ("Crushed stone" → "Crushed"), so the title list is
    /// derived here rather than duplicated in the view.
    static var titles: [String] {
        AggregateMaterial.allCases.map { $0.rawValue.components(separatedBy: " ").first ?? $0.rawValue }
    }

    static func material(index: Int) -> AggregateMaterial {
        let all = AggregateMaterial.allCases
        return all.indices.contains(index) ? all[index] : all[0]
    }
}

// MARK: - Framing

/// Stair code — IRC 2021 (0) / IBC (1).
enum StairCodeChoice {
    static let titles = ["IRC 2021", "IBC"]

    static func code(index: Int) -> StairCode {
        index == 0 ? .irc2021 : .ibc
    }
}
