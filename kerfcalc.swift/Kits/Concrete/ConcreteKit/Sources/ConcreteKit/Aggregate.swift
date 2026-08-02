import Foundation

/// Bulk aggregate materials. **Densities are typical loose values; actual weight varies with
/// supplier, gradation and moisture — treat as editable defaults, verify tonnage locally.**
/// Typical figures: crushed stone ≈ 2700 lb/yd³ (1.35 t), sand ≈ 2600 (1.30), dense-graded base
/// ≈ 3240 (1.62), pea gravel ≈ 2840 (1.42).
public enum AggregateMaterial: String, CaseIterable, Identifiable, Sendable {
    case crushedStone = "Crushed stone", sand = "Sand", roadBase = "Road base", peaGravel = "Pea gravel"
    public var id: String { rawValue }
    public var tonsPerCubicYard: Double {
        switch self {
        case .crushedStone: return 1.35
        case .sand:         return 1.30
        case .roadBase:     return 1.62
        case .peaGravel:    return 1.42
        }
    }
}

public enum Aggregate {
    public static func cubicYards(lengthFt: Double, widthFt: Double, depthIn: Double) -> Double {
        lengthFt * widthFt * (depthIn / 12) / 27
    }
    public static func tons(cubicYards yd3: Double, material: AggregateMaterial) -> Double {
        yd3 * material.tonsPerCubicYard
    }
    public static func tons(cubicYards yd3: Double, tonsPerYard: Double) -> Double { yd3 * tonsPerYard }
}

/// Masonry mortar quantity. Source: QUIKRETE Mason Mix (Type S, #1136) data sheet — one 80-lb bag
/// lays ≈ 13 standard 8×8×16 block or ≈ 37 standard brick.
public enum Mortar {
    public static let blockPer80lbBag = 13.0
    public static let brickPer80lbBag = 37.0
    public static func bagsForBlock(_ count: Int) -> Int { Int((Double(count) / blockPer80lbBag).rounded(.up)) }
    public static func bagsForBrick(_ count: Int) -> Int { Int((Double(count) / brickPer80lbBag).rounded(.up)) }
}
