import Foundation

/// The 37 tidal constituents NOAA publishes harmonic constants for, with their
/// Doodson argument coefficients, node-factor rule and nodal-phase rule.
/// Pure, stateless.
///
/// Source: Schureman, USC&GS Special Publication No. 98 (1958), **Table 2**
/// ("Harmonic constituents", pp. 164–166) for the arguments V, the u terms and
/// the f-formula references (U.S. Government work, public domain).
///
/// Each argument is `V₀ = cT·T + cs·s + ch·h + cp·p + cp1·p₁ + constant`, with T
/// the mean-solar hour angle and s, h, p, p₁ the mean longitudes (`Astronomy`).
///
/// The Doodson coefficients are independently checked against NOAA's own
/// published `speed` field for every constituent — see the `speeds match NOAA`
/// test. That check is what validates this table without trusting a transcription.
public enum ConstituentID: String, CaseIterable, Sendable {
    case M2, S2, N2, K1, M4, O1, M6, MK3, S4, MN4, NU2, S6, MU2, N2_2 = "2N2"
    case OO1, LAM2, S1, M1, J1, MM, SSA, SA, MSF, MF, RHO, Q1, T2, R2
    case Q1_2 = "2Q1", P1, SM2_2 = "2SM2", M3, L2, MK3_2 = "2MK3", K2, M8, MS4
}

/// How a constituent's nodal phase correction `u` is formed.
public enum NodalPhaseRule: Sendable, Equatable {
    case zero
    case xiNu(xi: Double, nu: Double)      // a·ξ + b·ν
    case negNuPrime                        // −ν′            (K₁)
    case negTwoNuDoublePrime               // −2ν″           (K₂)
    case negNuMinusQu                      // −ν − Qu        (M₁)
    case xiNuMinusRu(xi: Double, nu: Double)   // a·ξ + b·ν − Ru  (L₂)
    case xiNuPlusNuPrime(xi: Double, nu: Double, nuPrime: Double)  // MK₃, 2MK₃
}

/// How a constituent's node factor `f` is formed.
public enum NodeFactorRule: Sendable, Equatable {
    case unity
    case m2(power: Int)
    case o1, k1, k2, j1, oo1, mm, mf, m3, m1, l2
    case m2PowerTimesK1(power: Int)
}

/// A tidal constituent's definition: argument coefficients and nodal rules.
public struct ConstituentDefinition: Sendable, Equatable {
    public let id: ConstituentID
    /// Doodson coefficients of (T, s, h, p, p₁).
    public let coefficients: (Double, Double, Double, Double, Double)
    /// Additive constant in the argument, degrees.
    public let constantDeg: Double
    public let phaseRule: NodalPhaseRule
    public let factorRule: NodeFactorRule

    public static func == (a: ConstituentDefinition, b: ConstituentDefinition) -> Bool {
        a.id == b.id && a.coefficients == b.coefficients
            && a.constantDeg == b.constantDeg
            && a.phaseRule == b.phaseRule && a.factorRule == b.factorRule
    }

    /// Angular speed in degrees per mean solar hour, from the Doodson coefficients.
    public var speedDegPerHour: Double {
        let (cT, cs, ch, cp, cp1) = coefficients
        return cT * Astronomy.Rate.hourAngle + cs * Astronomy.Rate.s
             + ch * Astronomy.Rate.h + cp * Astronomy.Rate.p + cp1 * Astronomy.Rate.p1
    }

    /// Equilibrium argument `V₀ + u` in degrees at `elements`, with nodal `nodal`.
    public func equilibriumArgumentDeg(_ e: Astronomy.Elements, _ nodal: Nodal) -> Double {
        let (cT, cs, ch, cp, cp1) = coefficients
        let v = cT * e.hourAngleDeg + cs * e.sDeg + ch * e.hDeg
              + cp * e.pDeg + cp1 * e.p1Deg + constantDeg
        return v + nodalPhaseDeg(nodal)
    }

    /// The nodal phase correction `u`, degrees.
    public func nodalPhaseDeg(_ n: Nodal) -> Double {
        switch phaseRule {
        case .zero:
            return 0
        case let .xiNu(a, b):
            return a * n.xiDeg + b * n.nuDeg
        case .negNuPrime:
            return -n.nuPrimeDeg
        case .negTwoNuDoublePrime:
            // `twoNuDoublePrimeDeg` already holds 2ν″, so u(K₂) = −2ν″ is one negation.
            return -n.twoNuDoublePrimeDeg
        case .negNuMinusQu:
            return -n.nuDeg - n.quDeg
        case let .xiNuMinusRu(a, b):
            return a * n.xiDeg + b * n.nuDeg - n.ruDeg
        case let .xiNuPlusNuPrime(a, b, c):
            return a * n.xiDeg + b * n.nuDeg + c * n.nuPrimeDeg
        }
    }

    /// The node factor `f` (dimensionless).
    public func nodeFactor(_ n: Nodal) -> Double {
        switch factorRule {
        case .unity:                      return 1.0
        case let .m2(power):              return pow(n.fM2, Double(power))
        case .o1:                         return n.fO1
        case .k1:                         return n.fK1
        case .k2:                         return n.fK2
        case .j1:                         return n.fJ1
        case .oo1:                        return n.fOO1
        case .mm:                         return n.fMm
        case .mf:                         return n.fMf
        case .m3:                         return n.fM3
        case .m1:                         return n.fM1
        case .l2:                         return n.fL2
        case let .m2PowerTimesK1(power):  return pow(n.fM2, Double(power)) * n.fK1
        }
    }
}

public enum Constituents: Sendable {

    /// Every constituent NOAA publishes, keyed by its NOAA name.
    public static let all: [ConstituentDefinition] = [
        d(.M2,    (2, -2,  2,  0, 0),    0, .xiNu(xi: 2, nu: -2), .m2(power: 1)),
        d(.S2,    (2,  0,  0,  0, 0),    0, .zero,                .unity),
        d(.N2,    (2, -3,  2,  1, 0),    0, .xiNu(xi: 2, nu: -2), .m2(power: 1)),
        d(.K1,    (1,  0,  1,  0, 0),  -90, .negNuPrime,          .k1),
        d(.M4,    (4, -4,  4,  0, 0),    0, .xiNu(xi: 4, nu: -4), .m2(power: 2)),
        d(.O1,    (1, -2,  1,  0, 0),   90, .xiNu(xi: 2, nu: -1), .o1),
        d(.M6,    (6, -6,  6,  0, 0),    0, .xiNu(xi: 6, nu: -6), .m2(power: 3)),
        d(.MK3,   (3, -2,  3,  0, 0),  -90, .xiNuPlusNuPrime(xi: 2, nu: -2, nuPrime: -1),
                                                                 .m2PowerTimesK1(power: 1)),
        d(.S4,    (4,  0,  0,  0, 0),    0, .zero,                .unity),
        d(.MN4,   (4, -5,  4,  1, 0),    0, .xiNu(xi: 4, nu: -4), .m2(power: 2)),
        d(.NU2,   (2, -3,  4, -1, 0),    0, .xiNu(xi: 2, nu: -2), .m2(power: 1)),
        d(.S6,    (6,  0,  0,  0, 0),    0, .zero,                .unity),
        d(.MU2,   (2, -4,  4,  0, 0),    0, .xiNu(xi: 2, nu: -2), .m2(power: 1)),
        d(.N2_2,  (2, -4,  2,  2, 0),    0, .xiNu(xi: 2, nu: -2), .m2(power: 1)),
        d(.OO1,   (1,  2,  1,  0, 0),  -90, .xiNu(xi: -2, nu: -1), .oo1),
        d(.LAM2,  (2, -1,  0,  1, 0),  180, .xiNu(xi: 2, nu: -2), .m2(power: 1)),
        d(.S1,    (1,  0,  0,  0, 0),    0, .zero,                .unity),
        d(.M1,    (1, -1,  1,  1, 0),  -90, .negNuMinusQu,        .m1),
        d(.J1,    (1,  1,  1, -1, 0),  -90, .xiNu(xi: 0, nu: -1), .j1),
        d(.MM,    (0,  1,  0, -1, 0),    0, .zero,                .mm),
        d(.SSA,   (0,  0,  2,  0, 0),    0, .zero,                .unity),
        d(.SA,    (0,  0,  1,  0, 0),    0, .zero,                .unity),
        d(.MSF,   (0,  2, -2,  0, 0),    0, .zero,                .mm),
        d(.MF,    (0,  2,  0,  0, 0),    0, .xiNu(xi: -2, nu: 0), .mf),
        d(.RHO,   (1, -3,  3, -1, 0),   90, .xiNu(xi: 2, nu: -1), .o1),
        d(.Q1,    (1, -3,  1,  1, 0),   90, .xiNu(xi: 2, nu: -1), .o1),
        d(.T2,    (2,  0, -1,  0, 1),    0, .zero,                .unity),
        d(.R2,    (2,  0,  1,  0, -1), 180, .zero,                .unity),
        d(.Q1_2,  (1, -4,  1,  2, 0),   90, .xiNu(xi: 2, nu: -1), .o1),
        d(.P1,    (1,  0, -1,  0, 0),   90, .zero,                .unity),
        d(.SM2_2, (2,  2, -2,  0, 0),    0, .xiNu(xi: -2, nu: 2), .m2(power: 1)),
        d(.M3,    (3, -3,  3,  0, 0),    0, .xiNu(xi: 3, nu: -3), .m3),
        d(.L2,    (2, -1,  2, -1, 0),  180, .xiNuMinusRu(xi: 2, nu: -2), .l2),
        d(.MK3_2, (3, -4,  3,  0, 0),   90, .xiNuPlusNuPrime(xi: 4, nu: -4, nuPrime: 1),
                                                                 .m2PowerTimesK1(power: 2)),
        d(.K2,    (2,  0,  2,  0, 0),    0, .negTwoNuDoublePrime, .k2),
        d(.M8,    (8, -8,  8,  0, 0),    0, .xiNu(xi: 8, nu: -8), .m2(power: 4)),
        d(.MS4,   (4, -2,  2,  0, 0),    0, .xiNu(xi: 2, nu: -2), .m2(power: 1)),
    ]

    private static func d(_ id: ConstituentID,
                          _ c: (Double, Double, Double, Double, Double),
                          _ k: Double,
                          _ p: NodalPhaseRule,
                          _ f: NodeFactorRule) -> ConstituentDefinition {
        ConstituentDefinition(id: id, coefficients: c, constantDeg: k, phaseRule: p, factorRule: f)
    }

    private static let byName: [String: ConstituentDefinition] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id.rawValue, $0) })

    /// Look up a constituent by its NOAA name (e.g. `"M2"`, `"2N2"`, `"LAM2"`).
    public static func named(_ name: String) -> ConstituentDefinition? {
        byName[name.uppercased()]
    }
}
