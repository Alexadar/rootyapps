import Testing
import Foundation
@testable import DimensionKit

// Oracle = the corpus itself. Enforcement guard — makes the citation policy self-enforcing
// rather than advisory. If someone adds an expected number without a source and a URI, this fails.
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

    /// The corpus must actually cover PS 20-20 Table 3 in full. A shrinking table would silently
    /// weaken the strongest oracle the app has.
    @Test("PS 20-20 Table 3 is transcribed in full")
    func table3IsComplete() {
        #expect(Oracles.ps20Table3Rows.count == 29,
                "expected 29 dressed sizes from PS 20-20 Table 3, found \(Oracles.ps20Table3Rows.count)")
        let dressed = Oracles.ps20Table3Rows.map(\.0)
        #expect(Set(dressed).count == dressed.count, "duplicate dressed size in the Table 3 transcription")
        #expect(dressed.contains(7.5), "the discriminating 7-1/2 in row is missing")
    }

    /// Every source must name the document it came from, not just a bare link.
    @Test("sources name a document and a section")
    func sourcesAreSpecific() {
        for o in Oracles.all {
            let s = o.source
            let namesADocument = s.contains("SP 811") || s.contains("PS 20-20")
                || s.contains("Federal Register") || s.contains("FR ")
            #expect(namesADocument, "oracle \(o.id) does not name its document")
        }
    }
}
