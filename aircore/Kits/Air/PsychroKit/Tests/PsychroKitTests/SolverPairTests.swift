import Testing
import Foundation
@testable import PsychroKit

/// The "any two knowns" axis of the state space.
///
/// The scaffold solved exactly one pair — dry bulb + RH — so every other path through the solver
/// is new code with no history. This suite walks **all 21 pairs** over every reference state and
/// every altitude, rather than sampling the ones that felt likely.
@Suite("Any two knowns")
struct SolverPairTests {

    /// The seven knowns, read off an already-solved state.
    static func knowns(of s: MoistAir) -> [PsychroInput] {
        var all: [PsychroInput] = [
            .dryBulb(s.dryBulb), .wetBulb(s.wetBulb), .relativeHumidity(s.relativeHumidity),
            .humidityRatio(s.humidityRatio), .enthalpy(s.enthalpy),
            .specificVolume(s.specificVolume),
        ]
        if let dp = s.dewPoint { all.append(.dewPoint(dp)) }
        return all
    }

    /// How exactly a re-solve must reproduce the moisture content.
    ///
    /// 1 part in 10⁶ everywhere — except for a state sitting **on the saturation curve at the
    /// freezing point**, where the answer cannot be that good and no implementation's could be:
    /// Hyland–Wexler changes equation at 0 °C and the two branches disagree by 9.7 × 10⁻⁵, so the
    /// saturation curve has a step in it exactly there. Which side of zero a root find lands on
    /// then shifts the recovered humidity ratio by that step. Only the states within a degree of
    /// the branch change get the wider band, so a regression anywhere else still fails.
    static func moistureTolerance(for state: MoistAir) -> Double {
        state.isSaturated && abs(state.dryBulb) < 1
            ? Psychrometrics.saturationTolerance
            : 1e-6
    }

    @Test("Every solvable pair recovers the same state", arguments: Reference.states)
    func everyPairRecoversTheState(_ ref: Reference.State) throws {
        let truth = try MoistAir(dryBulb: ref.dryBulb, relativeHumidity: ref.relativeHumidity,
                                 pressure: ref.pressure)
        let knowns = Self.knowns(of: truth)
        var pairsChecked = 0

        for i in knowns.indices {
            for j in knowns.indices where j > i {
                let a = knowns[i], b = knowns[j]

                // Dew point + humidity ratio say the same thing twice: rightly refused.
                if a.isDryBulbIndependent && b.isDryBulbIndependent {
                    #expect(throws: PsychroError.underdetermined) {
                        try MoistAir.solve(a, b, pressure: ref.pressure)
                    }
                    continue
                }
                // Wet bulb + enthalpy trace near-coincident lines: also refused, on purpose.
                if PsychroInput.degeneratePairs.contains([a.kind, b.kind]) {
                    #expect(throws: PsychroError.degeneratePair(a.kind, b.kind)) {
                        try MoistAir.solve(a, b, pressure: ref.pressure)
                    }
                    continue
                }

                let solved = try MoistAir.solve(a, b, pressure: ref.pressure)
                pairsChecked += 1
                #expect(abs(solved.dryBulb - truth.dryBulb) < 1e-4,
                        "\(ref.name) from \(a.kind)+\(b.kind): dry bulb \(solved.dryBulb) vs \(truth.dryBulb)")
                #expect(relativeError(solved.humidityRatio, truth.humidityRatio) < Self.moistureTolerance(for: truth)
                            || abs(solved.humidityRatio - truth.humidityRatio) < 1e-9,
                        "\(ref.name) from \(a.kind)+\(b.kind): W \(solved.humidityRatio) vs \(truth.humidityRatio)")
            }
        }
        #expect(pairsChecked >= 19, "expected the full pair matrix, ran \(pairsChecked)")
    }

    /// The round trips §5 of the build prompt names by hand: solve for one property, feed it back
    /// as the known, and land on the original.
    @Test func namedRoundTrips() throws {
        let s = try MoistAir(dryBulb: 23.8888888889, relativeHumidity: 0.5,
                             pressure: Reference.seaLevel)

        // RH → wet bulb → RH
        let viaWetBulb = try MoistAir.solve(.dryBulb(s.dryBulb), .wetBulb(s.wetBulb),
                                            pressure: Reference.seaLevel)
        #expect(abs(viaWetBulb.relativeHumidity - 0.5) < 1e-9)

        // W → dew point → W
        let dewPoint = try #require(s.dewPoint)
        let viaDewPoint = try MoistAir.solve(.dryBulb(s.dryBulb), .dewPoint(dewPoint),
                                             pressure: Reference.seaLevel)
        #expect(relativeError(viaDewPoint.humidityRatio, s.humidityRatio) < 1e-9)

        // enthalpy + humidity ratio → the same dry bulb, with no temperature known at all
        let viaEnthalpy = try MoistAir.solve(.enthalpy(s.enthalpy),
                                             .humidityRatio(s.humidityRatio),
                                             pressure: Reference.seaLevel)
        #expect(abs(viaEnthalpy.dryBulb - s.dryBulb) < 1e-6)
    }

    /// A pair with no dry bulb at all, at all three altitudes — the case that needs the root find
    /// and the one a per-pair switch statement would most likely get wrong.
    @Test("Wet bulb + RH at every altitude",
          arguments: [Reference.seaLevel, Reference.denver, Reference.mexicoCity])
    func wetBulbPlusRelativeHumidity(_ pressure: Double) throws {
        let truth = try MoistAir(dryBulb: 23.8888888889, relativeHumidity: 0.5, pressure: pressure)
        let solved = try MoistAir.solve(.wetBulb(truth.wetBulb),
                                        .relativeHumidity(0.5), pressure: pressure)
        #expect(abs(solved.dryBulb - truth.dryBulb) < 1e-4)
        #expect(relativeError(solved.humidityRatio, truth.humidityRatio) < 1e-6)
    }

    /// 32 °F / 100 % is a state a technician enters, and it sits exactly on the correlation's
    /// branch change. It must still solve from every pair — the failure mode being guarded is a
    /// saturated freezing state being rejected as supersaturated because a root find landed a
    /// fraction of a millidegree on the ice side of zero.
    @Test func saturatedAtFreezingSolvesFromEveryPair() throws {
        let truth = try MoistAir(dryBulb: 0, relativeHumidity: 1.0, pressure: Reference.seaLevel)
        for known in Self.knowns(of: truth) where known.kind != .dryBulb {
            let solved = try MoistAir.solve(.dryBulb(0), known, pressure: Reference.seaLevel)
            #expect(solved.isSaturated, "from \(known.kind): degree of saturation \(solved.degreeOfSaturation)")
        }
    }

    /// Below freezing the wet-bulb relation switches equation (ASHRAE eq. 35), so the pair matrix
    /// gets walked again on the cold side rather than assumed to behave.
    @Test func pairsSolveBelowFreezing() throws {
        let truth = try MoistAir(dryBulb: -6.6666666667, relativeHumidity: 0.6,
                                 pressure: Reference.seaLevel)
        for known in Self.knowns(of: truth) where known.kind != .dryBulb {
            let solved = try MoistAir.solve(.dryBulb(truth.dryBulb), known,
                                            pressure: Reference.seaLevel)
            #expect(relativeError(solved.humidityRatio, truth.humidityRatio) < 1e-6,
                    "from \(known.kind) below freezing")
        }
    }
}
