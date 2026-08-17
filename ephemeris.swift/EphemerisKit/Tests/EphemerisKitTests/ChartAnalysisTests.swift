import Testing
import Foundation
import EphemerisKit

@Suite("Chart analysis")
struct ChartAnalysisTests {

    // MARK: Fixtures

    /// Assigns longitudes to bodies in `CelestialBody.allCases` order — the bodies are
    /// irrelevant to the pattern, only the longitudes are.
    private func chart(_ longitudes: [Double]) -> [BodyPosition] {
        zip(CelestialBody.allCases, longitudes).map {
            BodyPosition(body: $0, longitude: $1, speed: 1)
        }
    }

    private func shape(_ longitudes: [Double]) -> ChartShape {
        guard let s = ChartShape.classify(longitudes: longitudes) else {
            Issue.record("classifier returned nil for \(longitudes)")
            return ChartShape.classify(longitudes: [0, 1, 2])!
        }
        return s
    }

    private let bundle       = (0..<10).map { Double($0) * 12 }
    private let bowl         = (0..<10).map { Double($0) * 18 }
    private let locomotive   = (0..<10).map { Double($0) * 240 / 9 }
    private let splash       = (0..<10).map { Double($0) * 36 }
    private let bucket       = (0..<9).map { Double($0) * 20 } + [250]
    private let seesaw       = [0, 10, 20, 30, 40, 180, 190, 200, 210, 220].map(Double.init)
    private let splay        = [0, 10, 20, 130, 140, 150, 250, 260, 270].map(Double.init)

    /// Compares a measured shape against its oracle entry.
    private func expect(_ id: String, _ s: ChartShape, extra: [String: Double] = [:]) {
        let o = analysisOracles.all.first { $0.id == id }
        guard let o else { Issue.record("missing oracle '\(id)'"); return }
        let index = Double(ChartPattern.allCases.firstIndex(of: s.pattern)!)
        #expect(o.matches("patternIndex", index),
                "\(id): got \(s.pattern.rawValue) (index \(index))")
        #expect(o.matches("occupiedSpan", s.occupiedSpan), "\(id): span \(s.occupiedSpan)")
        #expect(o.matches("largestGap", s.largestGap), "\(id): g1 \(s.largestGap)")
        #expect(o.matches("secondLargestGap", s.secondLargestGap), "\(id): g2 \(s.secondLargestGap)")
        for (key, value) in extra {
            #expect(o.matches(key, value), "\(id): \(key) = \(value)")
        }
    }

    // MARK: Oracle corpus shape

    /// The oracles encode patterns as an index into `allCases`, so the declaration order is
    /// part of the contract — reordering the enum must fail loudly, not silently re-label.
    @Test func patternDeclarationOrderIsPinned() {
        #expect(ChartPattern.allCases == [.bundle, .bowl, .bucket, .locomotive,
                                          .seesaw, .splash, .splay])
    }

    @Test func analysisOraclesSatisfyTheCorpusContract() {
        for o in analysisOracles.all {
            #expect(o.id.hasPrefix("analysis-"), "oracle '\(o.id)' is not namespaced")
            #expect(!o.source.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(!o.inputs.isEmpty)
            #expect(!o.precision.isEmpty)
            #expect(!o.values.isEmpty)
            for key in o.values.keys { #expect((o.tolerances[key] ?? 0) > 0, "\(o.id).\(key)") }
            for key in o.tolerances.keys { #expect(o.values[key] != nil, "\(o.id).\(key)") }
        }
        let ids = analysisOracles.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: Triplicity / quadruplicity

    @Test func elementAndModalityCountsMatchPtolemy() {
        let a = ChartAnalysis(positions: chart((0..<10).map { 15 + Double($0) * 30 }))
        let oracle = analysisOracles.all.first { $0.id == "analysis-triplicity-quadruplicity" }!
        #expect(oracle.matches("fire", Double(a.elements[.fire])))
        #expect(oracle.matches("earth", Double(a.elements[.earth])))
        #expect(oracle.matches("air", Double(a.elements[.air])))
        #expect(oracle.matches("water", Double(a.elements[.water])))
        #expect(oracle.matches("cardinal", Double(a.modalities[.cardinal])))
        #expect(oracle.matches("fixed", Double(a.modalities[.fixed])))
        #expect(oracle.matches("mutable", Double(a.modalities[.mutable])))
        #expect(oracle.matches("elementTotal", Double(a.elements.total)))
        #expect(oracle.matches("modalityTotal", Double(a.modalities.total)))
    }

    /// The signs are assigned by `rawValue % 4` / `% 3`; spot-check the four corners of that
    /// arithmetic against the published triplicity/quadruplicity table.
    @Test func signAssignments() {
        #expect(ZodiacSign.aries.element == .fire)
        #expect(ZodiacSign.taurus.element == .earth)
        #expect(ZodiacSign.gemini.element == .air)
        #expect(ZodiacSign.pisces.element == .water)
        #expect(ZodiacSign.capricorn.modality == .cardinal)
        #expect(ZodiacSign.aquarius.modality == .fixed)
        #expect(ZodiacSign.pisces.modality == .mutable)
    }

    /// Property: whatever the chart, every body lands in exactly one element and one modality.
    @Test func balancesAlwaysSumToBodyCount() {
        var seed: UInt64 = 0x5EED_1234
        func next() -> Double {                      // deterministic LCG, no test flake
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(UInt64(1) << 53) * 360
        }
        for _ in 0..<400 {
            let count = Int(next() / 36) + 1                 // 1…10 bodies
            let positions = chart((0..<count).map { _ in next() - 180 })  // negatives included
            let a = ChartAnalysis(positions: positions)
            #expect(a.elements.total == a.bodyCount)
            #expect(a.modalities.total == a.bodyCount)
            #expect(a.scores.count == a.bodyCount)
            #expect(a.elements.counts.count == Element.allCases.count)
            #expect(a.modalities.counts.count == Modality.allCases.count)
        }
    }

    @Test func balanceReportsDominantAndMissing() {
        // Sun/Moon/Mars in Aries, Leo, Sagittarius — all fire, nothing else occupied.
        let a = ChartAnalysis(positions: chart([5, 125, 245]))
        #expect(a.elements[.fire] == 3)
        #expect(a.elements.strongest == .fire)
        #expect(Set(a.elements.missing) == [.earth, .air, .water])
        // Aries (cardinal), Leo (fixed), Sagittarius (mutable) — a three-way tie is not a winner.
        #expect(a.modalities.strongest == nil)
        #expect(a.modalities.missing.isEmpty)
    }

    // MARK: The seven patterns

    @Test func bundleIsEverythingInsideOneTrine() {
        expect("analysis-pattern-bundle", shape(bundle))
    }

    /// The same bundle rotated across 0° Aries. This is the regression this module most needs:
    /// the gaps are cyclic, so the seam must be invisible.
    @Test func bundleSurvivesTheZeroSeam() {
        expect("analysis-pattern-bundle-wrapped", shape(bundle.map { $0 + 350 }))
    }

    @Test func bowlIsOneHemisphere() {
        expect("analysis-pattern-bowl", shape(bowl))
    }

    @Test func bucketIsANineBodyGroupPlusALoneHandle() {
        let s = shape(bucket)
        expect("analysis-pattern-bucket", s, extra: ["handleCount": Double(s.handle?.count ?? 0)])
        #expect(s.handle?.start == 250)
        let a = ChartAnalysis(positions: chart(bucket))
        #expect(a.handleBodies == [.pluto])       // 10th body in allCases order = the 250° one
    }

    /// A bucket also has a gap ≥ 180°, so the bowl rule alone would claim it. Precedence, not
    /// the thresholds, is what separates the two — assert it directly.
    @Test func bucketWinsOverBowlWhenAHandleExists() {
        let nine = (0..<9).map { Double($0) * 12.5 }        // 0…100°
        let s = shape(nine + [170])
        #expect(s.largestGap == 190)                        // would read as a bowl on gap alone
        #expect(s.occupiedSpan == 170)                      // …but 170° is no longer a bundle
        #expect(s.pattern == .bucket)
        #expect(s.handle?.count == 1)
        // The handle is doing all the work: those same nine bodies alone span 100° — a bundle.
        #expect(shape(nine).pattern == .bundle)
    }

    @Test func locomotiveIsTwoThirdsWithAnEmptyTrine() {
        expect("analysis-pattern-locomotive", shape(locomotive))
    }

    @Test func seesawIsTwoOpposedGroups() {
        let s = shape(seesaw)
        expect("analysis-pattern-seesaw", s)
        #expect(s.clusters.count == 2)
        #expect(s.clusters.allSatisfy { $0.count == 5 })
        #expect(s.handle == nil)
    }

    @Test func splashIsEvenlySpread() {
        expect("analysis-pattern-splash", shape(splash))
    }

    @Test func splayIsThreeGroups() {
        let s = shape(splay)
        expect("analysis-pattern-splay", s, extra: ["clusterCount": Double(s.clusters.count)])
    }

    // MARK: Thresholds and degeneracies

    @Test func inclusiveBoundaries() {
        // Span exactly 120° is a bundle — even though its two 60° internal gaps would otherwise
        // make three groups and read as a splay. Bundle is tested first, by construction.
        let atBundleEdge = shape([0, 60, 120])
        #expect(atBundleEdge.occupiedSpan == 120)
        #expect(atBundleEdge.pattern == .bundle)

        // Gap exactly 120° is a locomotive; one degree less is a splash.
        let nine = (0..<9).map { Double($0) * 30 }          // 0…240, gap 120
        #expect(shape(nine).largestGap == 120)
        #expect(shape(nine).pattern == .locomotive)
        #expect(shape([0, 30, 60, 90, 120, 150, 180, 210, 241]).largestGap == 119)
        #expect(shape([0, 30, 60, 90, 120, 150, 180, 210, 241]).pattern == .splash)
    }

    /// A handle may be a tight conjunction, not only a single body; beyond the conjunction orb
    /// it is a group and the chart is a seesaw.
    @Test func handleWidthDecidesBucketVersusSeesaw() {
        let eight = (0..<8).map { Double($0) * 15 }          // 0…105
        #expect(shape(eight + [200, 206]).pattern == .bucket)   // handle spans 6° ≤ 8°
        #expect(shape(eight + [200, 210]).pattern == .seesaw)   // handle spans 10° > 8°
    }

    @Test func degenerateInputs() {
        #expect(ChartShape.classify(longitudes: []) == nil)
        #expect(ChartShape.classify(longitudes: [0, 180]) == nil)     // two points are ambiguous
        let stacked = shape([90, 90, 90, 90])
        #expect(stacked.pattern == .bundle)
        #expect(stacked.occupiedSpan == 0)
        #expect(stacked.clusters.count == 1)
        let empty = ChartAnalysis(positions: [])
        #expect(empty.bodyCount == 0)
        #expect(empty.shape == nil)
        #expect(empty.dominant == nil)
        #expect(empty.elements.total == 0)
    }

    /// Property: the pattern is a property of the shape, so rotating the whole chart — including
    /// past 0°/360° and into negative longitudes — must change nothing at all.
    @Test func classificationIsRotationInvariant() {
        let samples = [bundle, bowl, bucket, locomotive, seesaw, splash, splay]
        for sample in samples {
            let base = shape(sample)
            for offset in [-400.0, -179.5, 0, 7.3, 90, 179.9, 270, 359.5, 720] {
                let rotated = shape(sample.map { $0 + offset })
                #expect(rotated.pattern == base.pattern,
                        "offset \(offset): \(rotated.pattern.rawValue) != \(base.pattern.rawValue)")
                #expect(abs(rotated.largestGap - base.largestGap) < 1e-6, "offset \(offset)")
                #expect(abs(rotated.occupiedSpan - base.occupiedSpan) < 1e-6, "offset \(offset)")
                #expect(rotated.clusters.count == base.clusters.count, "offset \(offset)")
            }
        }
    }

    // MARK: Aspect weight

    /// Sun aspects all four others (one of them 1° off); Jupiter aspects nothing.
    @Test func dominantAndUnaspected() {
        let positions = chart([0, 60, 90, 120, 181, 15])   // sun, moon, mercury, venus, mars, jupiter
        let a = ChartAnalysis(positions: positions, orbFactor: 1)

        #expect(a.unaspected == [.jupiter])
        #expect(a.dominant == .sun)
        let sun = a.scores.first { $0.body == .sun }!
        #expect(sun.aspectCount == 4)
        // Three exact aspects (1 each) plus a 1°-orb opposition: 1 − 1/8 = 0.875.
        #expect(abs(sun.score - 3.875) < 1e-9)
        let jupiter = a.scores.first { $0.body == .jupiter }!
        #expect(jupiter.aspectCount == 0)
        #expect(jupiter.score == 0)
        // Ranking is total and descending.
        for i in 1..<a.scores.count { #expect(a.scores[i - 1].score >= a.scores[i].score) }
        #expect(a.scores.last?.body == .jupiter)
    }

    /// Tightening the orb factor can only remove aspects, never add them — and an unaspected
    /// body stays unaspected.
    @Test func orbFactorMonotonicity() {
        let positions = chart([0, 7, 63, 128, 186, 271, 300, 330, 15, 45])
        var previous = Int.max
        for factor in [1.5, 1.2, 1.0, 0.8, 0.5, 0.2] {
            let a = ChartAnalysis(positions: positions, orbFactor: factor)
            let total = a.scores.reduce(0) { $0 + $1.aspectCount }
            #expect(total <= previous, "orb factor \(factor) added aspects")
            previous = total
            #expect(a.unaspected.count == a.scores.filter { $0.aspectCount == 0 }.count)
            // The pattern is independent of the orb factor.
            #expect(a.pattern == ChartShape.classify(longitudes: positions.map(\.longitude))?.pattern)
        }
    }
}
