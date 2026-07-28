import Testing
import Foundation
@testable import TidesKit

// Oracle = the corpus itself. Enforcement guard -- makes the citation policy
// self-enforcing rather than advisory.
@Suite("Oracle corpus integrity")
struct OracleIntegrityTests {

    @Test("every oracle is cited, unique and complete")
    func everyOracleIsCitedAndComplete() {
        var ids = Set<String>()
        for o in Oracles.all {
            #expect(!o.source.isEmpty, "oracle \(o.id) has no cited source")
            #expect(o.source.contains("http"), "oracle \(o.id) source has no URI")
            #expect(!o.inputs.isEmpty, "oracle \(o.id) has no inputs")
            #expect(!o.precision.isEmpty, "oracle \(o.id) has no stated precision")
            #expect(!o.values.isEmpty, "oracle \(o.id) has no values")
            #expect(ids.insert(o.id).inserted, "duplicate oracle id \(o.id)")
            for k in o.values.keys {
                #expect(o.tolerances[k] != nil, "\(o.id).\(k) has no tolerance")
            }
            for k in o.tolerances.keys {
                #expect(o.values[k] != nil, "\(o.id).\(k) has a tolerance but no value")
            }
        }
    }

    @Test("tolerances are non-negative and finite")
    func tolerancesAreSane() {
        for o in Oracles.all {
            for (k, t) in o.tolerances {
                #expect(t >= 0, "\(o.id).\(k) has a negative tolerance")
                #expect(t.isFinite, "\(o.id).\(k) has a non-finite tolerance")
            }
        }
    }
}

// Oracle = NOAA CO-OPS published station data (embedded verbatim).
// Guards the fixtures themselves, so a regeneration that silently truncates
// or reorders the NOAA output fails loudly.
@Suite("Fixture integrity")
struct FixtureIntegrityTests {

    @Test("every station fixture carries the full published constituent set")
    func fixturesAreComplete() {
        #expect(Parse.constituents(Fixtures.sfHarconMetric).count == 37)
        #expect(Parse.constituents(Fixtures.sfHarconEnglish).count == 37)
        #expect(Parse.constituents(Fixtures.galvestonHarconMetric).count == 37)
        #expect(Parse.constituents(Fixtures.currentHarcon).count == 37)
    }

    @Test("prediction fixtures cover the stated window")
    func predictionWindowsAreIntact() {
        #expect(Parse.series(Fixtures.sfHourlyMetric).count == 168)
        #expect(Parse.series(Fixtures.sfHourlyEnglish).count == 168)
        #expect(Parse.series(Fixtures.galvestonHourlyMetric).count == 168)
        #expect(Parse.hilo(Fixtures.sfHiLoMetric).count >= 24)
        #expect(Parse.series(Fixtures.currentPredictions).count >= 300)
    }

    @Test("the Kit defines every constituent NOAA publishes")
    func kitCoversNOAAsConstituentSet() {
        for line in Fixtures.sfHarconMetric.split(separator: "\n") {
            let name = String(line.split(separator: ",")[0])
            #expect(Constituents.named(name) != nil,
                    "TidesKit does not define NOAA constituent '\(name)'")
        }
        #expect(Constituents.all.count == 37)
    }
}
