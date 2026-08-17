import Testing
import Foundation
import EphemerisKit

/// Decode a planet index carried by an oracle value.
private func body(_ v: Double) -> CelestialBody { CelestialBody.allCases[Int(v.rounded())] }
private func sign(_ v: Double) -> ZodiacSign { ZodiacSign(rawValue: Int(v.rounded()))! }

/// Absolute longitude of a degree within a sign.
private func lon(_ s: ZodiacSign, _ d: Double) -> Double { Double(s.rawValue) * 30 + d }

@Suite("Dignities")
struct DignitiesTests {

    // MARK: - Well-known anchors
    // Deliberately hand-written rather than oracle-driven: if the encoding helpers or the
    // oracle file were both wrong in the same way, these still fail.

    @Test func sunAnchors() {
        #expect(EssentialDignities.domicileRuler(of: .leo) == .sun)
        #expect(EssentialDignities.domiciles(of: .sun) == [.leo])
        #expect(EssentialDignities.exaltation(of: .sun)?.sign == .aries)
        #expect(EssentialDignities.exaltation(of: .sun)?.degree == 19)
        #expect(EssentialDignities.detriments(of: .sun) == [.aquarius])
        #expect(EssentialDignities.fall(of: .sun)?.sign == .libra)
    }

    @Test func saturnAnchors() {
        #expect(EssentialDignities.domiciles(of: .saturn) == [.capricorn, .aquarius])
        #expect(EssentialDignities.detriments(of: .saturn) == [.cancer, .leo])
        #expect(EssentialDignities.exaltation(of: .saturn)?.sign == .libra)
        #expect(EssentialDignities.fall(of: .saturn)?.sign == .aries)
    }

    @Test func remainingClassicalAnchors() {
        #expect(EssentialDignities.domiciles(of: .moon) == [.cancer])
        #expect(EssentialDignities.exaltation(of: .moon)?.sign == .taurus)
        #expect(EssentialDignities.fall(of: .moon)?.sign == .scorpio)

        #expect(EssentialDignities.domiciles(of: .mercury) == [.gemini, .virgo])
        #expect(EssentialDignities.exaltation(of: .mercury)?.sign == .virgo)
        #expect(EssentialDignities.fall(of: .mercury)?.sign == .pisces)

        #expect(EssentialDignities.domiciles(of: .venus) == [.taurus, .libra])
        #expect(EssentialDignities.exaltation(of: .venus)?.sign == .pisces)
        #expect(EssentialDignities.fall(of: .venus)?.sign == .virgo)

        #expect(EssentialDignities.domiciles(of: .mars) == [.aries, .scorpio])
        #expect(EssentialDignities.exaltation(of: .mars)?.sign == .capricorn)
        #expect(EssentialDignities.fall(of: .mars)?.sign == .cancer)

        #expect(EssentialDignities.domiciles(of: .jupiter) == [.sagittarius, .pisces])
        #expect(EssentialDignities.exaltation(of: .jupiter)?.sign == .cancer)
        #expect(EssentialDignities.fall(of: .jupiter)?.sign == .capricorn)
    }

    @Test func outerPlanetsHaveNoClassicalDignities() {
        for b in [CelestialBody.uranus, .neptune, .pluto] {
            #expect(!EssentialDignities.isClassical(b))
            #expect(EssentialDignities.domiciles(of: b).isEmpty)
            #expect(EssentialDignities.exaltation(of: b) == nil)
            #expect(EssentialDignities.fall(of: b) == nil)
            // nil, not zero: "not in the system" must not read as "measured and neutral".
            #expect(EssentialDignities.score(b, longitude: 100, sect: .day) == nil)
        }
        #expect(EssentialDignities.classicalBodies.count == 7)
    }

    // MARK: - Oracle: domicile / detriment / exaltation / fall

    @Test func domicileMatchesLilly() {
        let o = dignitiesOracles.require("dignities-lilly-domicile")
        for s in ZodiacSign.allCases {
            let expected = body(o.values[s.name.lowercased()]!)
            #expect(EssentialDignities.domicileRuler(of: s) == expected,
                    "\(s.name) domicile: expected \(expected.name)")
        }
    }

    @Test func detrimentMatchesLilly() {
        let o = dignitiesOracles.require("dignities-lilly-detriment")
        for s in ZodiacSign.allCases {
            #expect(EssentialDignities.detrimentRuler(of: s) == body(o.values[s.name.lowercased()]!),
                    "\(s.name) detriment")
        }
    }

    @Test func exaltationMatchesLilly() throws {
        let o = dignitiesOracles.require("dignities-lilly-exaltation")
        for b in EssentialDignities.classicalBodies {
            let e = try #require(EssentialDignities.exaltation(of: b))
            #expect(e.sign == sign(o.values["\(b.rawValue)Sign"]!), "\(b.name) exaltation sign")
            #expect(o.matches("\(b.rawValue)Degree", e.degree), "\(b.name) exaltation degree")
        }
        // Every exalted sign resolves back to its planet.
        for b in EssentialDignities.classicalBodies {
            let s = EssentialDignities.exaltation(of: b)!.sign
            #expect(EssentialDignities.exaltationRuler(of: s) == b)
            #expect(EssentialDignities.fallRuler(of: EssentialDignities.opposite(s)) == b)
        }
    }

    @Test func fallMatchesLilly() {
        let o = dignitiesOracles.require("dignities-lilly-fall")
        for b in EssentialDignities.classicalBodies {
            #expect(EssentialDignities.fall(of: b)?.sign == sign(o.values[b.rawValue]!),
                    "\(b.name) fall")
        }
    }

    // MARK: - Oracle: triplicity

    @Test func triplicityMatchesPtolemy() {
        let o = dignitiesOracles.require("dignities-ptolemy-triplicity")
        for s in ZodiacSign.allCases {
            let e = EssentialDignities.element(of: s).rawValue
            #expect(EssentialDignities.triplicityRuler(of: s, sect: .day) == body(o.values["\(e)Day"]!),
                    "\(s.name) day triplicity")
            #expect(EssentialDignities.triplicityRuler(of: s, sect: .night) == body(o.values["\(e)Night"]!),
                    "\(s.name) night triplicity")
        }
        // Mars rules the watery triplicity in both sects — the detail that separates the
        // Ptolemaic pair from the Dorothean triad.
        #expect(EssentialDignities.triplicityRuler(of: .cancer, sect: .day) == .mars)
        #expect(EssentialDignities.triplicityRuler(of: .cancer, sect: .night) == .mars)
    }

    @Test func dorotheanTriplicityMatchesCarmen() {
        let o = dignitiesOracles.require("dignities-dorotheus-triplicity")
        for s in ZodiacSign.allCases {
            let e = EssentialDignities.element(of: s).rawValue
            let t = EssentialDignities.dorotheanTriplicityRulers(of: s)
            #expect(t.day == body(o.values["\(e)Day"]!), "\(s.name) Dorothean day")
            #expect(t.night == body(o.values["\(e)Night"]!), "\(s.name) Dorothean night")
            #expect(t.participating == body(o.values["\(e)Participating"]!), "\(s.name) Dorothean participating")
        }
        // The two schemes must NOT have been silently merged.
        #expect(EssentialDignities.dorotheanTriplicityRulers(of: .pisces).day == .venus)
        #expect(EssentialDignities.triplicityRuler(of: .pisces, sect: .day) == .mars)
    }

    @Test func elementsFollowSignOrder() {
        #expect(EssentialDignities.element(of: .aries) == .fire)
        #expect(EssentialDignities.element(of: .taurus) == .earth)
        #expect(EssentialDignities.element(of: .gemini) == .air)
        #expect(EssentialDignities.element(of: .cancer) == .water)
        for s in ZodiacSign.allCases {
            // Signs of one triplicity sit 120° apart; opposite signs never share an element.
            let trine = ZodiacSign(rawValue: (s.rawValue + 4) % 12)!
            #expect(EssentialDignities.element(of: s) == EssentialDignities.element(of: trine))
            #expect(EssentialDignities.element(of: s)
                    != EssentialDignities.element(of: EssentialDignities.opposite(s)))
            #expect(EssentialDignities.opposite(EssentialDignities.opposite(s)) == s)
        }
        // Four signs to a triplicity, three triplicity members... twelve signs, four elements.
        for e in EssentialDignities.Element.allCases {
            #expect(ZodiacSign.allCases.filter { EssentialDignities.element(of: $0) == e }.count == 3)
        }
    }

    // MARK: - Oracle: terms

    @Test func termsMatchEgyptianTable() {
        for s in ZodiacSign.allCases {
            let o = dignitiesOracles.require("dignities-egyptian-terms-\(s.name.lowercased())")
            let bounds = EssentialDignities.terms(of: s)
            #expect(bounds.count == 5, "\(s.name) must have five terms")
            for (i, b) in bounds.enumerated() {
                #expect(b.ruler == body(o.values["ruler\(i + 1)"]!), "\(s.name) term \(i + 1) ruler")
                #expect(o.matches("end\(i + 1)", b.end), "\(s.name) term \(i + 1) end")
            }
        }
    }

    @Test func termDegreeTotalsMatchPtolemy() {
        let o = dignitiesOracles.require("dignities-egyptian-term-totals")
        var totals: [CelestialBody: Double] = [:]
        for b in EssentialDignities.allTerms { totals[b.ruler, default: 0] += b.span }
        for (bodyName, expected) in [("saturn", CelestialBody.saturn), ("jupiter", .jupiter),
                                     ("mars", .mars), ("venus", .venus), ("mercury", .mercury)] {
            #expect(o.matches(bodyName, totals[expected] ?? 0),
                    "\(bodyName) term total was \(totals[expected] ?? 0)")
        }
        #expect(o.matches("sum", totals.values.reduce(0, +)))
        // The luminaries hold no terms at all in the Egyptian scheme.
        #expect(totals[.sun] == nil && totals[.moon] == nil)
    }

    @Test func termsPartitionEverySign() {
        for s in ZodiacSign.allCases {
            let bounds = EssentialDignities.terms(of: s)
            #expect(bounds.first?.start == 0, "\(s.name) terms must start at 0°")
            #expect(bounds.last?.end == 30, "\(s.name) terms must end at 30°")
            for i in 1..<bounds.count {
                #expect(bounds[i].start == bounds[i - 1].end, "\(s.name) term \(i) leaves a gap")
                #expect(bounds[i].span > 0, "\(s.name) term \(i) is empty")
            }
            #expect(Set(bounds.map(\.ruler)).count == 5, "\(s.name) repeats a term ruler")
        }
        #expect(EssentialDignities.allTerms.count == 60)
    }

    /// Every degree of the zodiac lies in exactly one term — no gap, no overlap.
    @Test func everyDegreeHasExactlyOneTerm() {
        let all = EssentialDignities.allTerms
        for step in 0..<3600 {
            let l = Double(step) / 10
            let hits = all.filter { l >= $0.startLongitude && l < $0.startLongitude + $0.span }
            #expect(hits.count == 1, "longitude \(l) is in \(hits.count) terms")
            #expect(hits.first?.ruler == EssentialDignities.termRuler(at: l),
                    "lookup disagrees with the table at \(l)")
        }
    }

    // MARK: - Oracle: faces

    @Test func facesMatchLilly() {
        let o = dignitiesOracles.require("dignities-lilly-faces")
        let all = EssentialDignities.allFaces
        #expect(all.count == 36)
        for (i, f) in all.enumerated() {
            #expect(f.ruler == body(o.values[String(format: "face%02d", i)]!),
                    "face \(i) (\(f.sign.name) \(Int(f.start))–\(Int(f.end))°)")
        }
    }

    /// The face table is transcribed, not generated — so assert it reproduces the descending
    /// Chaldean order starting from Mars at 0° Aries. A transcription slip and a generator
    /// slip cannot then cancel out.
    @Test func facesFollowChaldeanOrder() {
        let order = EssentialDignities.chaldeanOrder
        let marsIndex = order.firstIndex(of: .mars)!
        for (i, f) in EssentialDignities.allFaces.enumerated() {
            #expect(f.ruler == order[(marsIndex + i) % order.count], "face \(i)")
        }
        #expect(order.count == 7)
        #expect(order.first == .saturn && order.last == .moon)
    }

    @Test func everyDegreeHasExactlyOneFace() {
        let all = EssentialDignities.allFaces
        for step in 0..<3600 {
            let l = Double(step) / 10
            let hits = all.filter { l >= $0.startLongitude && l < $0.startLongitude + $0.span }
            #expect(hits.count == 1, "longitude \(l) is in \(hits.count) faces")
            #expect(hits.first?.ruler == EssentialDignities.faceRuler(at: l),
                    "lookup disagrees with the table at \(l)")
        }
        for f in all { #expect(f.span == 10) }
    }

    // MARK: - The 0/360 seam

    @Test func longitudeWrapsBothWays() {
        let (s1, d1) = EssentialDignities.signAndDegree(-0.5)
        #expect(s1 == .pisces)
        #expect(abs(d1 - 29.5) < 1e-9)

        // norm360 of a tiny negative can round to exactly 360.0 — must land on Aries 0°,
        // never Aries 360°.
        let (s2, d2) = EssentialDignities.signAndDegree(-1e-16)
        #expect(s2 == .aries)
        #expect(d2 >= 0 && d2 < 30)

        let (s3, d3) = EssentialDignities.signAndDegree(360)
        #expect(s3 == .aries && d3 == 0)

        #expect(EssentialDignities.signAndDegree(720 + 45).sign == .taurus)
        #expect(abs(EssentialDignities.signAndDegree(720 + 45).degree - 15) < 1e-9)
        // −765° ≡ 315° = Aquarius 15°.
        #expect(EssentialDignities.signAndDegree(-720 - 45).sign == .aquarius)
        #expect(abs(EssentialDignities.signAndDegree(-720 - 45).degree - 15) < 1e-9)
    }

    @Test func termAndFaceLookupsAreWrapSafe() {
        // Pisces 29° — the last term (Saturn) and last face (Mars) of the zodiac.
        #expect(EssentialDignities.termRuler(at: 359.9) == .saturn)
        #expect(EssentialDignities.faceRuler(at: 359.9) == .mars)
        #expect(EssentialDignities.termRuler(at: -0.1) == .saturn)
        #expect(EssentialDignities.faceRuler(at: -0.1) == .mars)

        // Aries 0° — the first term (Jupiter) and first face (Mars).
        #expect(EssentialDignities.termRuler(at: 0) == .jupiter)
        #expect(EssentialDignities.termRuler(at: 360) == .jupiter)
        #expect(EssentialDignities.termRuler(at: -1e-16) == .jupiter)
        #expect(EssentialDignities.faceRuler(at: 0) == .mars)

        // Identical results a whole number of revolutions apart.
        for l in stride(from: 0.0, to: 360.0, by: 7.3) {
            #expect(EssentialDignities.termRuler(at: l) == EssentialDignities.termRuler(at: l + 720))
            #expect(EssentialDignities.faceRuler(at: l) == EssentialDignities.faceRuler(at: l - 1080))
        }

        // Boundaries are half-open: 20° Aries belongs to the Mars term, not Mercury's.
        #expect(EssentialDignities.termRuler(at: lon(.aries, 19.999)) == .mercury)
        #expect(EssentialDignities.termRuler(at: lon(.aries, 20)) == .mars)
        #expect(EssentialDignities.faceRuler(at: lon(.aries, 9.999)) == .mars)
        #expect(EssentialDignities.faceRuler(at: lon(.aries, 10)) == .sun)
    }

    // MARK: - Scoring

    @Test func fortitudeWeightsMatchLilly() {
        let o = dignitiesOracles.require("dignities-lilly-fortitudes")
        for kind in DignityKind.allCases {
            #expect(o.matches(kind.rawValue, Double(kind.points)), "\(kind.rawValue) weight")
        }
        #expect(DignityKind.allCases.filter(\.isDebility).count == 3)
    }

    @Test func sunExaltedInAries() throws {
        // Aries 19° by day: exaltation (4) + fire day triplicity (3) + face 10–20° Aries (1).
        // The term there is Mercury's, so no term point.
        let s = try #require(EssentialDignities.score(.sun, longitude: lon(.aries, 19), sect: .day))
        #expect(s.kinds == [.exaltation, .triplicity, .face])
        #expect(s.total == 8)
        #expect(!s.isPeregrine)

        // Same degree at night: fire's night ruler is Jupiter, so the triplicity point goes.
        let n = try #require(EssentialDignities.score(.sun, longitude: lon(.aries, 19), sect: .night))
        #expect(n.total == 5)
    }

    @Test func sunInItsOwnSign() throws {
        let day = try #require(EssentialDignities.score(.sun, longitude: lon(.leo, 5), sect: .day))
        #expect(day.kinds == [.domicile, .triplicity])   // Leo 0–6° term is Jupiter's, face Saturn's
        #expect(day.total == 8)

        let night = try #require(EssentialDignities.score(.sun, longitude: lon(.leo, 20), sect: .night))
        #expect(night.kinds == [.domicile])
        #expect(night.total == 5)
    }

    @Test func debilities() throws {
        let detriment = try #require(EssentialDignities.score(.sun, longitude: lon(.aquarius, 5), sect: .day))
        #expect(detriment.kinds == [.detriment])
        #expect(detriment.total == -5)
        #expect(!detriment.isPeregrine)   // never charged twice for the same weakness

        let fall = try #require(EssentialDignities.score(.sun, longitude: lon(.libra, 21), sect: .day))
        #expect(fall.kinds == [.fall])
        #expect(fall.total == -4)

        // Mars at Libra 29° is in detriment (−5) but still holds its own term (+2).
        let mixed = try #require(EssentialDignities.score(.mars, longitude: lon(.libra, 29), sect: .day))
        #expect(mixed.kinds == [.term, .detriment])
        #expect(mixed.total == -3)
        #expect(!mixed.isPeregrine)
        #expect(mixed.dignities == [.term])
        #expect(mixed.debilities == [.detriment])
    }

    /// Mercury is the only body whose detriment and fall land in the same sign — Pisces,
    /// opposite both Virgo (his house) and Virgo (his exaltation). −9 is therefore the floor
    /// of the whole scheme, and a table edit that breaks the coincidence shows up here.
    @Test func mercuryIsDoublyDebilitatedInPisces() throws {
        let s = try #require(EssentialDignities.score(.mercury, longitude: lon(.pisces, 5), sect: .day))
        #expect(s.kinds == [.detriment, .fall])
        #expect(s.total == -9)

        // Even his own term there (Pisces 16–19°) only lifts him to −7.
        let inTerm = try #require(EssentialDignities.score(.mercury, longitude: lon(.pisces, 17), sect: .day))
        #expect(inTerm.kinds == [.term, .detriment, .fall])
        #expect(inTerm.total == -7)

        let doubled = EssentialDignities.classicalBodies.filter { b in
            ZodiacSign.allCases.contains { s in
                EssentialDignities.detrimentRuler(of: s) == b && EssentialDignities.fall(of: b)?.sign == s
            }
        }
        #expect(doubled == [.mercury])
    }

    @Test func peregrine() throws {
        // Moon at Gemini 25°: Mercury's sign, Saturn's term, the Sun's face, Saturn's day
        // triplicity — the Moon holds nothing and is not debilitated either.
        let s = try #require(EssentialDignities.score(.moon, longitude: lon(.gemini, 25), sect: .day))
        #expect(s.kinds == [.peregrine])
        #expect(s.total == -5)
        #expect(s.isPeregrine)
        #expect(EssentialDignities.hasNoEssentialDignity(.moon, longitude: lon(.gemini, 25), sect: .day))

        // The strict Lilly reading still calls a detrimented planet dignity-less…
        #expect(EssentialDignities.hasNoEssentialDignity(.sun, longitude: lon(.aquarius, 5), sect: .day))
        // …while the score does not add the peregrine penalty on top.
        #expect(EssentialDignities.score(.sun, longitude: lon(.aquarius, 5), sect: .day)?.total == -5)
    }

    @Test func termAndFaceStack() throws {
        // Venus at Taurus 3° — her own sign (5) and her own term, Taurus 0–8° (2).
        // By day she also rules the earthy triplicity (3); the face is Mercury's.
        let day = try #require(EssentialDignities.score(.venus, longitude: lon(.taurus, 3), sect: .day))
        #expect(day.kinds == [.domicile, .triplicity, .term])
        #expect(day.total == 10)

        let night = try #require(EssentialDignities.score(.venus, longitude: lon(.taurus, 3), sect: .night))
        #expect(night.kinds == [.domicile, .term])
        #expect(night.total == 7)
    }

    /// Structural invariants that must hold everywhere, not just at the anchors.
    @Test func scoreInvariantsHoldAcrossTheZodiac() throws {
        for b in EssentialDignities.classicalBodies {
            for sect in EssentialDignities.Sect.allCases {
                for step in stride(from: 0.0, to: 360.0, by: 0.5) {
                    let s = try #require(EssentialDignities.score(b, longitude: step, sect: sect))
                    // Peregrine is exclusive with everything else.
                    if s.isPeregrine { #expect(s.kinds == [.peregrine]) }
                    // Domicile and detriment are opposite signs, so never both.
                    #expect(!(s.has(.domicile) && s.has(.detriment)))
                    #expect(!(s.has(.exaltation) && s.has(.fall)))
                    // Achievable band: 11 at best (see `maximumDignity`), −9 at worst —
                    // Mercury in Pisces is detriment and fall at once.
                    #expect(s.total >= -9 && s.total <= 11)
                    #expect(s.sign == ZodiacSign.from(longitude: step))
                    #expect(s.total == s.kinds.reduce(0) { $0 + $1.points })
                }
            }
        }
    }

    /// The theoretical ceiling is 15 (all five dignities at once), but the tables never let
    /// all five coincide. Pinning the real ceiling turns any future edit to a table into a
    /// failing test rather than a silent shift in every chart's strongest planet.
    @Test func maximumDignity() throws {
        var best = -99
        var where_ = ""
        for b in EssentialDignities.classicalBodies {
            for step in stride(from: 0.0, to: 360.0, by: 0.25) {
                for sect in EssentialDignities.Sect.allCases {
                    let s = try #require(EssentialDignities.score(b, longitude: step, sect: sect))
                    if s.total > best {
                        best = s.total
                        where_ = "\(b.name) \(s.sign.name) \(Int(step) % 30)° \(sect.rawValue)"
                    }
                }
            }
        }
        // Reached by Mercury in Virgo 0–7° (domicile 5 + exaltation 4 + term 2) and by Mars
        // in Scorpio 0–7° (domicile 5 + triplicity 3 + term 2 + face 1).
        #expect(best == 11, "highest essential dignity found: \(best) at \(where_)")

        let mercury = try #require(EssentialDignities.score(.mercury, longitude: lon(.virgo, 3), sect: .day))
        #expect(mercury.kinds == [.domicile, .exaltation, .term])
        #expect(mercury.total == 11)

        let mars = try #require(EssentialDignities.score(.mars, longitude: lon(.scorpio, 3), sect: .night))
        #expect(mars.kinds == [.domicile, .triplicity, .term, .face])
        #expect(mars.total == 11)
    }

    @Test func bodyPositionConvenience() throws {
        let p = BodyPosition(body: .sun, longitude: lon(.leo, 5), speed: 1)
        #expect(p.dignity(sect: .day)?.total == 8)
        #expect(BodyPosition(body: .pluto, longitude: 0, speed: 1).dignity(sect: .day) == nil)
    }

    // MARK: - Corpus contract
    // The integration agent folds `dignitiesOracles.all` into `Oracles.all` later; these
    // enforce the same guard OracleGuardTests applies, so the merge cannot import a bad entry.

    @Test func oracleCorpusIsWellFormed() {
        #expect(!dignitiesOracles.all.isEmpty)
        for o in dignitiesOracles.all {
            #expect(o.id.hasPrefix("dignities-"), "'\(o.id)' must be namespaced")
            #expect(!o.source.trimmingCharacters(in: .whitespaces).isEmpty, "'\(o.id)' has no source")
            #expect(!o.inputs.isEmpty, "'\(o.id)' has no inputs")
            #expect(!o.precision.isEmpty, "'\(o.id)' has no precision rationale")
            #expect(!o.values.isEmpty, "'\(o.id)' has no values")
            for k in o.values.keys {
                #expect((o.tolerances[k] ?? 0) > 0, "'\(o.id)' value '\(k)' has no positive tolerance")
            }
            for k in o.tolerances.keys {
                #expect(o.values[k] != nil, "'\(o.id)' tolerance '\(k)' has no value")
            }
        }
        let ids = dignitiesOracles.all.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate id in the dignities corpus")
        // Merged into the shared corpus by the integration pass: each id must appear there
        // EXACTLY once — zero means the merge dropped them, two means a collision.
        for id in ids {
            #expect(Oracles.all.filter { $0.id == id }.count == 1,
                    "'\(id)' is not present exactly once in the shared corpus")
        }
    }
}
