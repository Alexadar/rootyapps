import Testing
import Foundation
import TVMKit

/// Enforcement guard for the oracle corpus, per `calculators/VALIDATION.md`:
/// "No green suite ships without a documented oracle." An entry without a citation, or a value
/// without a tolerance, fails here rather than quietly proving nothing.
///
/// ORACLES:
///  • GUARD — structural only; asserts nothing about the maths.
@Suite("Oracle corpus integrity")
struct OracleGuardTests {

    @Test func everyOracleCitesAnExternalSource() {
        for o in Oracles.all {
            #expect(!o.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "oracle '\(o.id)' has no source citation")
            #expect(o.source.contains("CFR"), "oracle '\(o.id)' source names no document")
            #expect(o.source.contains("http"), "oracle '\(o.id)' source has no URI")
            #expect(!o.inputs.isEmpty, "oracle '\(o.id)' has no inputs")
            #expect(!o.precision.isEmpty, "oracle '\(o.id)' has no precision rationale")
        }
    }

    @Test func everyValueHasAMatchingTolerance() {
        for o in Oracles.all {
            #expect(!o.values.isEmpty, "oracle '\(o.id)' has no values")
            for key in o.values.keys {
                #expect(o.tolerances[key] != nil, "oracle '\(o.id)' value '\(key)' has no tolerance")
                #expect((o.tolerances[key] ?? -1) > 0,
                        "oracle '\(o.id)' tolerance '\(key)' must be positive")
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

    /// Coverage guard. Each of the five registers must be classified: `.ratePct` is the one with no
    /// closed form, so it carries **published** oracles; the other four are closed-form inversions of
    /// the same balance equation and are pinned by the five-way round trip plus the published factors
    /// they are built from. Adding a sixth register fails this test until someone classifies it —
    /// which is the point.
    @Test func everyRegisterIsClassified() {
        let publishedRateOracles = Oracles.all.filter { $0.values["annualRatePct"] != nil }
        #expect(publishedRateOracles.count >= 3,
                "the rate solve has no closed form and needs published cases")

        let closedForm: Set<TVM.Variable> = [.periods, .presentValue, .payment, .futureValue]
        let published: Set<TVM.Variable> = [.ratePct]
        #expect(closedForm.union(published) == Set(TVM.Variable.allCases),
                "a register exists that is neither published nor covered by the round trip")
        #expect(closedForm.isDisjoint(with: published))
    }

    /// The published factor oracles must actually cover both factors the equation is made of.
    @Test func bothFactorsHavePublishedOracles() {
        #expect(Oracles.all.contains { $0.values["discountFactor"] != nil })
        #expect(Oracles.all.contains { $0.values["annuityFactor"] != nil })
    }
}
