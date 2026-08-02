import Foundation
import MaterialsKit
import ConcreteKit

/// Pure hero (label + value + unit) selection for the mode-switch tools.
///
/// These mirror the per-mode `switch` that used to live inside the SwiftUI views. Extracted so the
/// *mapping* — which Kit function and which unit belong to each mode — is unit-testable, not just the
/// underlying Kit math. See `kerfcalcTests/ToolHeroesTests.swift`. The views call these verbatim, so a
/// wrong-function or wrong-unit wiring bug fails a test instead of shipping.
private func f(_ x: Double, _ p: Int = 2) -> String { String(format: "%.\(p)f", x) }

/// Estimate tool — Drywall (0) / Paint (1) / Block (2).
enum EstimateHero {
    static func hero(mode: Int, area: Double, coats: Int) -> (label: String, value: String, unit: String) {
        switch mode {
        case 0: return ("Drywall sheets", "\(Estimate.drywallSheets(areaFt2: area))", "sheets")
        case 1: return ("Paint", f(Estimate.paintGallons(areaFt2: area, coats: coats)), "gal")
        default: return ("CMU block", "\(Estimate.units(areaFt2: area, perFt2: Estimate.cmu8x16PerFt2))", "block")
        }
    }
}

/// Mortar & grout tool — Block (0) / Brick (1) / Grout (2).
enum MortarHero {
    static func hero(mode: Int, count: Double, wallArea: Double) -> (label: String, value: String, unit: String) {
        switch mode {
        case 0: return ("Mortar bags", "\(Mortar.bagsForBlock(Int(count)))", "bags")
        case 1: return ("Mortar bags", "\(Mortar.bagsForBrick(Int(count)))", "bags")
        default: return ("Grout", f(Grout.cubicYards(wallAreaFt2: wallArea), 2), "yd³")
        }
    }
}

/// Hardscape tool — Pavers (0) / Retaining wall (1).
enum PaversHero {
    static func hero(mode: Int, area: Double, pL: Double, pW: Double, waste: Double,
                     wallLenFt: Double, wallHIn: Double, blkL: Double, blkH: Double)
        -> (label: String, value: String, unit: String) {
        if mode == 0 {
            return ("Pavers", "\(Hardscape.paverCount(areaFt2: area, lengthIn: pL, widthIn: pW, wastePct: waste))", "pavers")
        } else {
            return ("Wall block", "\(Hardscape.wallBlockCount(wallLengthFt: wallLenFt, wallHeightIn: wallHIn, blockLengthIn: blkL, blockHeightIn: blkH))", "block")
        }
    }
}
