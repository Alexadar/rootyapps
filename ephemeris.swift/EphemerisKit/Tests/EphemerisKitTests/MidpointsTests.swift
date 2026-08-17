import Testing
import Foundation
import EphemerisKit

@Suite("Midpoints")
struct MidpointsTests {

    // A grid whose steps are coprime with 360 so it sweeps the whole circle, and whose
    // difference (11 − 7) still produces exactly opposed pairs — the ambiguous case is inside
    // the sweep, not bolted on beside it.
    static let gridA = stride(from: 0.0, to: 360.0, by: 7.0)
    static let gridB = stride(from: 0.0, to: 360.0, by: 11.0)

    // MARK: Defining properties

    /// The midpoint is equidistant from both inputs. True in every case, including at exact
    /// opposition where the tie-break decides *which* equidistant point is returned.
    @Test func isEquidistantFromBothInputs() {
        for a in Self.gridA {
            for b in Self.gridB {
                let m = Midpoints.midpoint(a, b)
                let da = AstroMath.separation(m, a)
                let db = AstroMath.separation(m, b)
                #expect(abs(da - db) < 1e-9, "mid(\(a),\(b)) = \(m): \(da) vs \(db)")
            }
        }
    }

    /// …and it sits on the SHORTER arc, i.e. each half is half the separation (≤ 90°), not
    /// 180 − sep/2 which is where the far midpoint sits.
    ///
    /// The far midpoint is checked to FAIL the same assertion, so this test cannot be satisfied
    /// by an implementation that consistently picks the wrong branch.
    @Test func liesOnTheShorterArc() {
        for a in Self.gridA {
            for b in Self.gridB where !Midpoints.isAmbiguous(a, b) {
                let sep = AstroMath.separation(a, b)
                let m = Midpoints.midpoint(a, b)
                #expect(abs(AstroMath.separation(m, a) - sep / 2) < 1e-9,
                        "mid(\(a),\(b)) = \(m) is on the long arc (sep \(sep))")
                #expect(AstroMath.separation(m, a) <= 90 + 1e-9)

                // Control: the far midpoint must not pass, otherwise the check is vacuous.
                if sep > 1e-9 {
                    let far = Midpoints.oppositeMidpoint(a, b)
                    #expect(abs(AstroMath.separation(far, a) - sep / 2) > 1e-9,
                            "shorter-arc check is not discriminating at (\(a),\(b))")
                }
            }
        }
    }

    /// The whole reason this function exists: 350° and 10° meet at 0°, not at the arithmetic
    /// mean 180°. Every wrap bug in this area is that one substitution.
    @Test func wrapsAcrossZeroAriesInsteadOfAveraging() {
        let o = midpointsOracles.require("midpoints-half-sum-shorter-arc")
        #expect(o.matches("350_10", Midpoints.midpoint(350, 10)))
        #expect(o.matches("10_350", Midpoints.midpoint(10, 350)))
        #expect(o.matches("359_1", Midpoints.midpoint(359, 1)))
        #expect(o.matches("100_200", Midpoints.midpoint(100, 200)))
        #expect(o.matches("0_90", Midpoints.midpoint(0, 90)))

        // Spelled out: the naive mean is 180° away, and would be the bug.
        #expect(abs(AstroMath.norm180(Midpoints.midpoint(350, 10) - (350 + 10) / 2) - 180) < 1e-9)
    }

    @Test func isCommutative() {
        for a in Self.gridA {
            for b in Self.gridB {
                #expect(abs(AstroMath.norm180(Midpoints.midpoint(a, b) - Midpoints.midpoint(b, a))) < 1e-12,
                        "mid(\(a),\(b)) = \(Midpoints.midpoint(a, b)) but mid(\(b),\(a)) = \(Midpoints.midpoint(b, a))")
            }
        }
        // Including the case that breaks a naive implementation: exact opposition, where the
        // sign of norm180(b − a) is the same for both orders and the answers diverge by 180°.
        for a in stride(from: 0.0, to: 360.0, by: 13.0) {
            #expect(Midpoints.midpoint(a, a + 180) == Midpoints.midpoint(a + 180, a))
        }
    }

    // MARK: The ambiguous case

    /// At exact opposition there is no shorter arc. The tie-break must be deterministic, order
    /// independent, and equal to the documented value — not whatever the floating-point sign
    /// happens to be that day.
    @Test func oppositionUsesTheDocumentedTieBreak() {
        let o = midpointsOracles.require("midpoints-opposition-tiebreak")
        #expect(o.matches("0_180", Midpoints.midpoint(0, 180)))
        #expect(o.matches("180_0", Midpoints.midpoint(180, 0)))
        #expect(o.matches("10_190", Midpoints.midpoint(10, 190)))
        #expect(o.matches("270_90", Midpoints.midpoint(270, 90)))

        // Still equidistant — the tie-break chooses between two valid answers, it does not
        // invent a third.
        for a in stride(from: 0.0, to: 360.0, by: 17.0) {
            let m = Midpoints.midpoint(a, a + 180)
            #expect(abs(AstroMath.separation(m, a) - 90) < 1e-9)
            #expect(abs(AstroMath.separation(m, a + 180) - 90) < 1e-9)
        }
    }

    @Test func ambiguityIsReportedNotHidden() {
        #expect(Midpoints.isAmbiguous(0, 180))
        #expect(Midpoints.isAmbiguous(123.5, 303.5))
        #expect(!Midpoints.isAmbiguous(0, 179.9))
        #expect(!Midpoints.isAmbiguous(0, 180.1))
        #expect(!Midpoints.isAmbiguous(0, 0))
    }

    /// Just outside the band the shorter arc is real again, and it is on *opposite sides* of the
    /// circle for 179.9° and 180.1°. A branch slip shows up here as a 180° error.
    @Test func nearOppositionFollowsTheShorterArcOnEitherSide() {
        let o = midpointsOracles.require("midpoints-near-opposition-branches")
        #expect(o.matches("0_179.9", Midpoints.midpoint(0, 179.9)))
        #expect(o.matches("0_180.1", Midpoints.midpoint(0, 180.1)))
        // The two answers are ~180° apart even though the inputs differ by 0.2° — the
        // discontinuity is inherent to the convention, which is why the band exists at all.
        #expect(abs(AstroMath.separation(Midpoints.midpoint(0, 179.9),
                                         Midpoints.midpoint(0, 180.1)) - 180) < 0.2)
    }

    /// A pair that is mathematically opposite but arrives with rounding noise must still land on
    /// one answer, not flip with the last bit. (Constructed the way a real chart would produce
    /// it: sum a long chain of increments rather than writing the number down.)
    @Test func floatingPointNoiseAtOppositionDoesNotFlipTheAnswer() {
        var a = 0.0
        for _ in 0..<10 { a += 0.1 }          // 0.9999999999999999, not 1.0
        let b = a + 180
        let m = Midpoints.midpoint(a, b)
        #expect(abs(AstroMath.norm180(m - (a + 90))) < 1e-9, "noisy opposition gave \(m)")
        #expect(Midpoints.midpoint(a, b) == Midpoints.midpoint(b, a))
    }

    // MARK: Normalization & degenerate inputs

    @Test func acceptsUnnormalizedInputAndAlwaysReturnsZeroTo360() {
        #expect(abs(Midpoints.midpoint(-10, 10)) < 1e-9)
        #expect(abs(Midpoints.midpoint(710, 370)) < 1e-9)          // ≡ (350, 10)
        #expect(abs(Midpoints.midpoint(-370, -350)) < 1e-9)
        for a in Self.gridA {
            for b in Self.gridB {
                let m = Midpoints.midpoint(a - 720, b + 1080)
                #expect(m >= 0 && m < 360, "mid = \(m)")
                #expect(abs(AstroMath.norm180(m - Midpoints.midpoint(a, b))) < 1e-9)
            }
        }
    }

    @Test func midpointOfAPointWithItselfIsThatPoint() {
        for a in Self.gridA {
            #expect(abs(AstroMath.norm180(Midpoints.midpoint(a, a) - a)) < 1e-12)
        }
        #expect(abs(AstroMath.norm180(Midpoints.midpoint(359.999, 359.999) - 359.999)) < 1e-12)
    }

    @Test func oppositeMidpointIsTheOtherHalfOfTheAxis() {
        let o = midpointsOracles.require("midpoints-half-sum-axis")
        #expect(o.matches("350_10", Midpoints.oppositeMidpoint(350, 10)))
        #expect(o.matches("100_200", Midpoints.oppositeMidpoint(100, 200)))
        for a in Self.gridA {
            for b in Self.gridB {
                #expect(abs(AstroMath.separation(Midpoints.midpoint(a, b),
                                                 Midpoints.oppositeMidpoint(a, b)) - 180) < 1e-9)
            }
        }
    }

    @Test func positionOverloadUsesTheLongitudes() {
        let a = BodyPosition(body: .sun, longitude: 350, speed: 1)
        let b = BodyPosition(body: .sun, longitude: 10, speed: 1)
        #expect(abs(Midpoints.midpoint(a, b)) < 1e-9)
    }

    // MARK: Composite

    static func positions(at date: Date) -> [BodyPosition] {
        CelestialBody.allCases.map {
            BodyPosition(body: $0,
                         longitude: Ephemeris.longitude(of: $0, at: date),
                         speed: Ephemeris.dailyMotion(of: $0, at: date))
        }
    }

    static let natalA = utc(1988, 5, 3, 6, 30)
    static let natalB = utc(1991, 11, 17, 21, 15)

    @Test func compositeBodiesSitAtTheirMidpoints() {
        let o = midpointsOracles.require("midpoints-composite-midpoint-method")
        let a = [BodyPosition(body: .sun, longitude: 10, speed: 1),
                 BodyPosition(body: .moon, longitude: 200, speed: 13),
                 BodyPosition(body: .mars, longitude: 350, speed: 0.5)]
        let b = [BodyPosition(body: .sun, longitude: 350, speed: 1),
                 BodyPosition(body: .moon, longitude: 100, speed: 12),
                 BodyPosition(body: .mars, longitude: 20, speed: -0.3)]
        let c = Composite.chart(of: a, and: b)
        #expect(o.matches("sun", c.longitude(of: .sun)!))
        #expect(o.matches("moon", c.longitude(of: .moon)!))
        #expect(o.matches("mars", c.longitude(of: .mars)!))
        #expect(c.ambiguousBodies.isEmpty)

        // …and it agrees with the primitive for every body of a real pair of charts.
        let ra = Self.positions(at: Self.natalA), rb = Self.positions(at: Self.natalB)
        let rc = Composite.chart(of: ra, and: rb)
        #expect(rc.positions.count == CelestialBody.allCases.count)
        for p in rc.positions {
            let la = ra.first { $0.body == p.body }!.longitude
            let lb = rb.first { $0.body == p.body }!.longitude
            #expect(abs(AstroMath.norm180(p.longitude - Midpoints.midpoint(la, lb))) < 1e-12)
            #expect(p.longitude >= 0 && p.longitude < 360)
        }
    }

    @Test func compositeIsCommutative() {
        let a = Self.positions(at: Self.natalA), b = Self.positions(at: Self.natalB)
        let ab = Composite.chart(of: a, and: b), ba = Composite.chart(of: b, and: a)
        for p in ab.positions {
            let q = ba.position(of: p.body)!
            #expect(abs(AstroMath.norm180(p.longitude - q.longitude)) < 1e-12, "\(p.body)")
            #expect(abs(p.speed - q.speed) < 1e-12)
        }
    }

    /// The composite of two moving points moves at their mean rate — that is why the speeds are
    /// averaged rather than re-derived. Checked against a real centred finite difference of the
    /// composite longitude itself, so a wrong averaging rule cannot hide behind the definition.
    ///
    /// The ±3h step matches `Ephemeris.dailyMotion`'s own estimator, which makes the identity
    /// exact rather than approximate: away from the branch the midpoint is linear in the two
    /// longitudes, so differencing it *is* averaging the two differences.
    @Test func compositeSpeedIsTheMidpointsActualMotion() {
        let h = 3 * 3600.0
        let before = Composite.chart(of: Self.positions(at: Self.natalA.addingTimeInterval(-h)),
                                     and: Self.positions(at: Self.natalB.addingTimeInterval(-h)))
        let after = Composite.chart(of: Self.positions(at: Self.natalA.addingTimeInterval(h)),
                                    and: Self.positions(at: Self.natalB.addingTimeInterval(h)))
        let now = Composite.chart(of: Self.positions(at: Self.natalA),
                                  and: Self.positions(at: Self.natalB))
        for p in now.positions {
            // Skip pairs sitting near opposition: there the midpoint legitimately jumps 180°
            // between samples, and a finite difference across the branch is meaningless.
            let la = Ephemeris.longitude(of: p.body, at: Self.natalA)
            let lb = Ephemeris.longitude(of: p.body, at: Self.natalB)
            guard abs(AstroMath.separation(la, lb) - 180) > 1 else { continue }

            let measured = AstroMath.norm180(after.longitude(of: p.body)! - before.longitude(of: p.body)!)
                         / (2 * h / 86_400)
            #expect(abs(measured - p.speed) < 1e-6,
                    "\(p.body): composite moves \(measured)°/day but reports \(p.speed)")
        }
    }

    @Test func compositeDropsBodiesMissingFromEitherChart() {
        let a = [BodyPosition(body: .sun, longitude: 10, speed: 1),
                 BodyPosition(body: .pluto, longitude: 250, speed: 0.01)]
        let b = [BodyPosition(body: .sun, longitude: 350, speed: 1)]
        let c = Composite.chart(of: a, and: b)
        #expect(c.positions.map(\.body) == [.sun])
        #expect(c.longitude(of: .pluto) == nil)
        #expect(c.position(of: .pluto) == nil)
    }

    /// Order follows the first chart, and a body repeated in either input is taken once.
    @Test func compositeKeepsFirstChartOrderAndDeduplicates() {
        let a = [BodyPosition(body: .mars, longitude: 10, speed: 1),
                 BodyPosition(body: .sun, longitude: 20, speed: 1),
                 BodyPosition(body: .mars, longitude: 300, speed: 1)]
        let b = [BodyPosition(body: .sun, longitude: 40, speed: 1),
                 BodyPosition(body: .mars, longitude: 30, speed: 1),
                 BodyPosition(body: .mars, longitude: 100, speed: 1)]
        let c = Composite.chart(of: a, and: b)
        #expect(c.positions.map(\.body) == [.mars, .sun])
        #expect(abs(c.longitude(of: .mars)! - 20) < 1e-9)   // first Mars of each side: 10 & 30
        #expect(abs(c.longitude(of: .sun)! - 30) < 1e-9)
    }

    @Test func compositeFlagsBodiesWhoseMidpointWasATieBreak() {
        let a = [BodyPosition(body: .sun, longitude: 10, speed: 1),
                 BodyPosition(body: .moon, longitude: 100, speed: 13)]
        let b = [BodyPosition(body: .sun, longitude: 190, speed: 1),
                 BodyPosition(body: .moon, longitude: 140, speed: 12)]
        let c = Composite.chart(of: a, and: b)
        #expect(c.ambiguousBodies == [.sun])
        #expect(abs(c.longitude(of: .sun)! - 100) < 1e-9)   // documented tie-break
    }

    /// Angles are midpoints too — and they only appear when both charts supply them, because a
    /// one-sided angle has no midpoint to be.
    @Test func compositeAnglesAreMidpointsOfBothChartsAngles() {
        let kyiv = GeoLocation(latitude: 50.45, longitude: 30.52, name: "Kyiv")
        let sydney = GeoLocation(latitude: -33.87, longitude: 151.21, name: "Sydney")
        let angA = Houses.angles(at: Self.natalA, location: kyiv)
        let angB = Houses.angles(at: Self.natalB, location: sydney)

        let bare = Composite.chart(of: Self.positions(at: Self.natalA),
                                   and: Self.positions(at: Self.natalB))
        #expect(bare.midheaven == nil && bare.ascendant == nil)
        #expect(Composite.chart(of: Self.positions(at: Self.natalA),
                                and: Self.positions(at: Self.natalB),
                                angles: angA).midheaven == nil)

        let c = Composite.chart(of: Self.positions(at: Self.natalA),
                                and: Self.positions(at: Self.natalB),
                                angles: angA, and: angB)
        #expect(abs(AstroMath.norm180(c.midheaven! - Midpoints.midpoint(angA.midheaven, angB.midheaven))) < 1e-12)
        #expect(abs(AstroMath.norm180(c.ascendant! - Midpoints.midpoint(angA.ascendant, angB.ascendant))) < 1e-12)
        #expect(abs(AstroMath.separation(c.midheaven!, angA.midheaven)
                    - AstroMath.separation(c.midheaven!, angB.midheaven)) < 1e-9)
    }

    // MARK: Oracle corpus contract
    //
    // `Oracles.all` is wired up by an integration pass, so the shared guard suite cannot see this
    // array yet. Enforce the same contract here — a corpus that would fail integration should
    // fail now, not later.

    @Test func oracleCorpusSatisfiesTheSharedContract() {
        for o in midpointsOracles.all {
            #expect(o.id.hasPrefix("midpoints-"), "oracle '\(o.id)' is not namespaced")
            #expect(!o.source.trimmingCharacters(in: .whitespaces).isEmpty, "\(o.id): no source")
            #expect(!o.inputs.isEmpty, "\(o.id): no inputs")
            #expect(!o.precision.isEmpty, "\(o.id): no precision rationale")
            #expect(!o.values.isEmpty, "\(o.id): no values")
            for key in o.values.keys {
                #expect((o.tolerances[key] ?? 0) > 0, "\(o.id): '\(key)' has no positive tolerance")
            }
            for key in o.tolerances.keys {
                #expect(o.values[key] != nil, "\(o.id): tolerance '\(key)' has no value")
            }
        }
        let ids = midpointsOracles.all.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate id inside the midpoints corpus")
        // Merged into the shared corpus by the integration pass: each id must appear there
        // EXACTLY once — zero means the merge dropped them, two means a collision.
        for id in ids {
            #expect(Oracles.all.filter { $0.id == id }.count == 1,
                    "midpoints oracle '\(id)' is not present exactly once in the shared corpus")
        }
    }
}
