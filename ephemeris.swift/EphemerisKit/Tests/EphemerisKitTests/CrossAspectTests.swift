import Testing
import Foundation
import EphemerisKit

@Suite("Cross-aspects")
struct CrossAspectTests {

    private func pos(_ body: CelestialBody, _ lon: Double) -> BodyPosition {
        BodyPosition(body: body, longitude: lon, speed: 1)
    }

    /// Deterministic longitudes — a seeded LCG, so a property failure is reproducible
    /// from the seed alone rather than "it went red once on CI".
    private func scatter(seed: UInt64, count: Int = 10) -> [BodyPosition] {
        var s = seed
        return CelestialBody.allCases.prefix(count).map { body in
            s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Double(s >> 11) / Double(UInt64(1) << 53)
            return pos(body, unit * 360)
        }
    }

    /// Widest factor the corpus cares about: 5.0 closes every gap between adjacent
    /// aspect angles, so every possible separation matches something.
    private let saturatingFactor = 5.0

    // ── Property 1: every returned pair really is at its aspect's angle ──────────

    @Test func everyResultSitsAtItsAspectAngleWithinOrb() {
        for seed in UInt64(1)...40 {
            let a = scatter(seed: seed)
            let b = scatter(seed: seed &* 31 &+ 7)
            for factor in [0.25, 1.0, 2.0, saturatingFactor] {
                for x in Aspects.detect(between: a, and: b, orbFactor: factor) {
                    let lonM = a.first { $0.body == x.moving }!.longitude
                    let lonR = b.first { $0.body == x.reference }!.longitude
                    let sep = AstroMath.separation(lonM, lonR)
                    #expect(abs(x.separation - sep) < 1e-9,
                            "seed \(seed): reported separation \(x.separation) ≠ \(sep)")
                    #expect(abs(x.orb - abs(sep - x.type.angle)) < 1e-9,
                            "seed \(seed): orb is not |separation − angle|")
                    #expect(x.orb <= x.type.baseOrb * factor + 1e-9,
                            "seed \(seed): \(x.id) orb \(x.orb) exceeds \(x.type.baseOrb * factor)")
                    #expect(abs(sep - x.type.angle) <= x.type.baseOrb * factor + 1e-9)
                }
            }
        }
    }

    /// The converse: nothing in orb is silently dropped. Every pair whose separation
    /// falls inside some aspect's orb must appear exactly once.
    @Test func nothingInOrbIsDropped() {
        let ptolemaic = crossaspectsOracles.require("crossaspects-ptolemaic-angles")
        for seed in UInt64(100)...120 {
            let a = scatter(seed: seed)
            let b = scatter(seed: seed &+ 5000)
            let found = Aspects.detect(between: a, and: b, orbFactor: 1)
            var expectedPairs = 0
            for m in a {
                for r in b {
                    let sep = AstroMath.separation(m.longitude, r.longitude)
                    let hit = AspectType.all.contains { abs(sep - $0.angle) <= $0.baseOrb }
                    if hit { expectedPairs += 1 }
                }
            }
            #expect(found.count == expectedPairs, "seed \(seed): dropped or duplicated a pair")
            #expect(Set(found.map(\.id)).count == found.count, "seed \(seed): duplicate pair id")
            // The aspect angles used are the classical five, nothing invented.
            for x in found {
                #expect(ptolemaic.matches(x.type.name.lowercased(), x.type.angle),
                        "\(x.type.name) is not at its Ptolemaic angle")
            }
        }
    }

    // ── Property 2: the full cross product is considered, not the i<j half ──────

    @Test func fullCrossProductIsConsidered() {
        let o = crossaspectsOracles.require("crossaspects-cartesian-cardinality")
        let a = scatter(seed: 7)
        let b = scatter(seed: 99)
        // At the saturating factor every separation matches some aspect, so the result
        // count IS the pair count: 10×10 = 100, not C(10,2) = 45.
        let cross = Aspects.detect(between: a, and: b, orbFactor: saturatingFactor)
        #expect(o.matches("orderedPairs", Double(cross.count)),
                "expected the full cross product, got \(cross.count)")
        let within = Aspects.detect(in: a, orbFactor: saturatingFactor)
        #expect(o.matches("withinSetPairs", Double(within.count)),
                "within-set detection changed shape: \(within.count)")
        #expect(o.matches("selfPairs", Double(cross.filter(\.isSelfPair).count)))
        // Both orderings of every distinct pair are present.
        #expect(cross.contains { $0.moving == .sun && $0.reference == .moon })
        #expect(cross.contains { $0.moving == .moon && $0.reference == .sun })
    }

    @Test func asymmetricSetSizesAreHandled() {
        let o = crossaspectsOracles.require("crossaspects-cartesian-cardinality")
        let three = Array(scatter(seed: 3).prefix(3))
        let ten = scatter(seed: 11)
        let cross = Aspects.detect(between: three, and: ten, orbFactor: saturatingFactor)
        #expect(o.matches("threeByTen", Double(cross.count)))
        #expect(Aspects.detect(between: [], and: ten, orbFactor: 1).isEmpty)
        #expect(Aspects.detect(between: ten, and: [], orbFactor: 1).isEmpty)
    }

    // ── Property 3: self-pairs survive (this is where returns live) ─────────────

    @Test func selfPairsAreAllowed() {
        // Transiting Saturn 2° past natal Saturn: a Saturn return, and the whole reason
        // the i<j guard must not carry over.
        let cross = Aspects.detect(between: [pos(.saturn, 252)], and: [pos(.saturn, 250)], orbFactor: 1)
        #expect(cross.count == 1)
        #expect(cross.first?.type.name == "Conjunction")
        #expect(cross.first?.isSelfPair == true)
        #expect(cross.first?.isReturn == true)
        #expect(abs((cross.first?.orb ?? 99) - 2) < 1e-9)

        // A chart against itself: ten exact self-conjunctions, orb 0.
        let chart = scatter(seed: 42)
        let identity = Aspects.detect(between: chart, and: chart, orbFactor: 1)
        let selves = identity.filter(\.isSelfPair)
        #expect(selves.count == 10)
        for s in selves {
            #expect(s.type.name == "Conjunction")
            #expect(s.orb < 1e-9)
            #expect(s.isReturn)
        }
        // detect(in:) cannot express any of them — that is the gap this API fills.
        #expect(Aspects.detect(in: chart, orbFactor: 1).allSatisfy { $0.a != $0.b })
    }

    // ── Property 4: swapping the arguments mirrors the result ──────────────────

    @Test func swappingArgumentsMirrorsTheResult() {
        for seed in UInt64(200)...215 {
            let a = scatter(seed: seed)
            let b = scatter(seed: seed &+ 1)
            for factor in [1.0, 2.0, saturatingFactor] {
                let forward = Aspects.detect(between: a, and: b, orbFactor: factor)
                let backward = Aspects.detect(between: b, and: a, orbFactor: factor)
                #expect(forward.count == backward.count)
                #expect(Set(forward.map(\.mirrored)) == Set(backward),
                        "seed \(seed) factor \(factor): swapping the sets is not a mirror")
                // Side labels genuinely follow the arguments rather than being cosmetic.
                for x in backward where !x.isSelfPair {
                    #expect(forward.contains { $0.moving == x.reference && $0.reference == x.moving })
                }
            }
        }
    }

    // ── Property 5: the 0/360 seam ─────────────────────────────────────────────

    @Test func wrapsAcrossZeroDegrees() {
        let o = crossaspectsOracles.require("crossaspects-circular-metric")

        // 359° vs 1° is a 2° conjunction. A naive |a−b| would call it 358° and find nothing.
        let wrap = Aspects.detect(between: [pos(.mars, 359)], and: [pos(.venus, 1)], orbFactor: 1)
        #expect(wrap.count == 1)
        #expect(wrap.first?.type.name == "Conjunction")
        #expect(o.matches("sep359to1", wrap.first?.separation ?? -1))
        #expect(abs((wrap.first?.orb ?? 99) - 2) < 1e-9)

        // Symmetric across the seam, both as an argument swap and as a longitude swap.
        let wrapBack = Aspects.detect(between: [pos(.venus, 1)], and: [pos(.mars, 359)], orbFactor: 1)
        #expect(o.matches("sep1to359", wrapBack.first?.separation ?? -1))

        // A sextile that only exists if the seam is handled: 300° to 0°.
        let seamSextile = Aspects.detect(between: [pos(.sun, 300)], and: [pos(.jupiter, 0)], orbFactor: 1)
        #expect(seamSextile.first?.type.name == "Sextile")
        #expect(o.matches("sep300to0", seamSextile.first?.separation ?? -1))

        // Clamped to ≤180: 190° apart is a 170° separation, never 190°.
        let clamped = Aspects.detect(between: [pos(.sun, 190)], and: [pos(.pluto, 0)], orbFactor: 2)
        #expect(o.matches("sep190to0", clamped.first?.separation ?? -1))
        #expect(clamped.first?.type.name == "Opposition")

        // Adding whole turns to one side changes nothing but the bookkeeping. Compared by
        // id + orb rather than by value equality: `lon + 720` is not bit-identical to `lon`
        // once the exponent shifts, so the separations agree to ~1e-13, not exactly.
        for seed in UInt64(300)...310 {
            let a = scatter(seed: seed)
            let b = scatter(seed: seed &+ 77)
            let shifted = b.map { BodyPosition(body: $0.body, longitude: $0.longitude + 720, speed: $0.speed) }
            let plain = Aspects.detect(between: a, and: b, orbFactor: 1)
            let wound = Aspects.detect(between: a, and: shifted, orbFactor: 1)
            #expect(plain.map(\.id) == wound.map(\.id), "seed \(seed): a whole turn changed the result")
            for (p, w) in zip(plain, wound) { #expect(abs(p.orb - w.orb) < 1e-9) }
        }

        // Every reported separation stays inside [0, 180] regardless of input winding.
        for seed in UInt64(400)...410 {
            let a = scatter(seed: seed).map { BodyPosition(body: $0.body, longitude: $0.longitude - 1080, speed: $0.speed) }
            let b = scatter(seed: seed &+ 9)
            for x in Aspects.detect(between: a, and: b, orbFactor: saturatingFactor) {
                #expect(x.separation >= 0 && x.separation <= 180 + 1e-9)
            }
        }
    }

    // ── Orb gating and type selection ──────────────────────────────────────────

    @Test func orbBoundaryMatchesTheWithinSetRule() {
        // Conjunction base orb 8°: 7° in, 9° out at factor 1.
        #expect(!Aspects.detect(between: [pos(.sun, 0)], and: [pos(.mercury, 7)], orbFactor: 1).isEmpty)
        #expect(Aspects.detect(between: [pos(.sun, 0)], and: [pos(.mercury, 9)], orbFactor: 1).isEmpty)
        // Tightening drops the 7° hit (7 > 8 × 0.8).
        #expect(Aspects.detect(between: [pos(.sun, 0)], and: [pos(.mercury, 7)], orbFactor: 0.8).isEmpty)
        // Exactly on the boundary is inside.
        #expect(!Aspects.detect(between: [pos(.sun, 0)], and: [pos(.mercury, 8)], orbFactor: 1).isEmpty)
    }

    @Test func tightestAspectTypeWinsWhenOrbsOverlap() {
        // At factor 5 sextile spans ±20 and square ±30, so 78° is inside both.
        // Square is 12° off, sextile 18° off → square, even though sextile is listed first.
        let overlap = Aspects.detect(between: [pos(.sun, 0)], and: [pos(.mars, 78)], orbFactor: 5)
        #expect(overlap.count == 1)
        #expect(overlap.first?.type.name == "Square")
        #expect(abs((overlap.first?.orb ?? 99) - 12) < 1e-9)
        // One row per pair, never one per matching type.
        let saturated = Aspects.detect(between: scatter(seed: 5), and: scatter(seed: 6), orbFactor: 5)
        #expect(saturated.count == 100)
    }

    @Test func sortedTightestFirstAndStable() {
        let a = scatter(seed: 21)
        let b = scatter(seed: 22)
        let cross = Aspects.detect(between: a, and: b, orbFactor: 2)
        for i in 1..<cross.count { #expect(cross[i - 1].orb <= cross[i].orb) }
        // Same inputs, same order — a list diffing against this must not shuffle.
        #expect(Aspects.detect(between: a, and: b, orbFactor: 2).map(\.id) == cross.map(\.id))
    }

    // ── The oracle rows must survive being appended to the shared corpus ───────

    /// `OracleGuardTests` only inspects `Oracles.all`, which does not contain these rows until
    /// an integration pass appends them. Run the same contract here so a violation fails now
    /// rather than in someone else's suite.
    @Test func crossAspectOraclesSatisfyTheCorpusContract() {
        let mine = crossaspectsOracles.all
        #expect(!mine.isEmpty)
        for o in mine {
            #expect(o.id.hasPrefix("crossaspects-"), "'\(o.id)' is not namespaced")
            #expect(!o.source.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(!o.inputs.isEmpty)
            #expect(!o.precision.isEmpty)
            #expect(!o.values.isEmpty)
            for key in o.values.keys { #expect((o.tolerances[key] ?? 0) > 0, "\(o.id).\(key)") }
            for key in o.tolerances.keys { #expect(o.values[key] != nil, "\(o.id).\(key)") }
        }
        let ids = mine.map(\.id)
        #expect(Set(ids).count == ids.count)
        // These rows are now merged into the shared corpus, so each must appear there EXACTLY
        // once: zero means the merge dropped them, two means an id collides with another module.
        for id in ids {
            #expect(Oracles.all.filter { $0.id == id }.count == 1,
                    "'\(id)' is not present exactly once in the shared corpus")
        }
    }

    // ── Astronomical anchor: the Saturn return is a self-pair conjunction ───────

    /// Tightest transiting-Saturn ☌ natal-Saturn found by a daily scan, in years after `natalDate`.
    private func saturnReturnYears(natalDate: Date) throws -> (years: Double, orb: Double) {
        let natal = [BodyPosition(body: .saturn,
                                  longitude: Ephemeris.longitude(of: .saturn, at: natalDate),
                                  speed: Ephemeris.dailyMotion(of: .saturn, at: natalDate))]
        var best: (date: Date, orb: Double)?
        var day = 27.0 * 365.25
        while day <= 32.0 * 365.25 {
            let t = natalDate.addingTimeInterval(day * 86_400)
            let transit = [BodyPosition(body: .saturn,
                                        longitude: Ephemeris.longitude(of: .saturn, at: t),
                                        speed: Ephemeris.dailyMotion(of: .saturn, at: t))]
            if let hit = Aspects.detect(between: transit, and: natal, orbFactor: 1).first(where: \.isReturn),
               best == nil || hit.orb < best!.orb {
                best = (t, hit.orb)
            }
            day += 1
        }
        let found = try #require(best)
        return (found.date.timeIntervalSince(natalDate) / 86_400 / 365.25, found.orb)
    }

    @Test func saturnReturnIsASelfPairConjunction() throws {
        let o = crossaspectsOracles.require("crossaspects-saturn-return")
        var all: [Double] = []
        for year in stride(from: 1900, through: 2000, by: 10) {
            let (years, orb) = try saturnReturnYears(natalDate: utc(year, 1, 1))
            all.append(years)
            #expect(o.matches("returnYears", years),
                    "natal \(year): return landed at \(years) yr, orb \(orb)°")
            // A one-day grid can miss exactness by half a step of Saturn's apparent motion
            // (≤0.13°/day), so anything under 0.08° means the scan really found the crossing.
            #expect(orb < 0.08, "natal \(year): scan should reach near-exactness, got \(orb)°")
        }
        let mean = all.reduce(0, +) / Double(all.count)
        #expect(o.matches("meanReturnYears", mean),
                "mean of \(all.count) returns is \(mean) yr")
    }
}
