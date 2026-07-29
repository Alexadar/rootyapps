import Testing
import Foundation
import DayCountKit

/// Enforcement guard for the oracle corpus, per `calculators/VALIDATION.md`:
/// "No green suite ships without a documented oracle." These tests make the policy self-enforcing —
/// an entry without a citation, or a value without a tolerance, fails here rather than quietly
/// proving nothing.
///
/// ORACLES:
///  • GUARD — structural only; asserts nothing about day counts.
@Suite("Oracle corpus integrity")
struct OracleGuardTests {

    @Test func everyOracleCitesAnExternalSource() {
        for o in Oracles.all {
            #expect(!o.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "oracle '\(o.id)' has no source citation")
            #expect(o.source.contains("http") || o.source.contains("CFR"),
                    "oracle '\(o.id)' source cites no locatable document")
            #expect(!o.inputs.isEmpty, "oracle '\(o.id)' has no inputs")
            #expect(!o.precision.isEmpty, "oracle '\(o.id)' has no precision rationale")
        }
    }

    @Test func everyValueHasAMatchingTolerance() {
        for o in Oracles.all {
            #expect(!o.values.isEmpty, "oracle '\(o.id)' has no values")
            for key in o.values.keys {
                #expect(o.tolerances[key] != nil, "oracle '\(o.id)' value '\(key)' has no tolerance")
                // 0 is legitimate here and only here: these published values are exact integers.
                #expect((o.tolerances[key] ?? -1) >= 0,
                        "oracle '\(o.id)' tolerance '\(key)' must be >= 0")
            }
            for key in o.tolerances.keys {
                #expect(o.values[key] != nil, "oracle '\(o.id)' tolerance '\(key)' has no value")
            }
        }
    }

    @Test func oracleIDsAreUnique() {
        let ids = Oracles.all.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate oracle id in the corpus")
    }

    @Test func requireResolvesEveryDeclaredID() {
        for o in Oracles.all { #expect(Oracles.require(o.id).id == o.id) }
    }

    /// Coverage guard: every convention the app can render must have a published oracle behind it,
    /// or it could drift with nothing watching. ISDA covers the three 30/360 variants and — via the
    /// `days_actual` column of the same rows — the actual-day numerator the other three share.
    @Test func everyConventionIsCoveredByAnOracle() {
        for convention in DayCount.Convention.allCases {
            let key = convention.isThirtyBasis ? "days_\(convention.rawValue)" : "days_actual"
            #expect(Oracles.all.contains { $0.values[key] != nil },
                    "no oracle covers \(convention.displayName) — add one before shipping")
        }
    }

    /// The ISDA corpus must stay complete: 22 published pairs, each with all ten columns.
    @Test func isdaCorpusIsComplete() {
        #expect(Oracles.isdaRows.count == 22, "ISDA published 22 date pairs on the Comparison sheet")
        let expected: Set<String> = [
            "days_thirty360", "d1_thirty360", "d2_thirty360",
            "days_thirtyE360", "d1_thirtyE360", "d2_thirtyE360",
            "days_thirtyE360ISDA", "d1_thirtyE360ISDA", "d2_thirtyE360ISDA",
            "days_actual",
        ]
        for o in Oracles.isdaRows {
            #expect(Set(o.values.keys) == expected, "oracle '\(o.id)' is missing published columns")
        }
    }
}
