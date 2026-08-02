import Testing
import Foundation
import EphemerisKit

/// Enforcement guard for the oracle corpus, per `calculators/VALIDATION.md`:
/// "No green suite ships without a documented oracle." These tests make the policy
/// self-enforcing — an entry without a citation, or a value without a tolerance, fails here
/// rather than quietly proving nothing.
@Suite("Oracle corpus integrity")
struct OracleGuardTests {

    @Test func everyOracleCitesAnExternalSource() {
        for o in Oracles.all {
            #expect(!o.source.trimmingCharacters(in: .whitespaces).isEmpty,
                    "oracle '\(o.id)' has no source citation")
            #expect(!o.inputs.isEmpty, "oracle '\(o.id)' has no inputs")
            #expect(!o.precision.isEmpty, "oracle '\(o.id)' has no precision rationale")
        }
    }

    @Test func everyValueHasAMatchingTolerance() {
        for o in Oracles.all {
            #expect(!o.values.isEmpty, "oracle '\(o.id)' has no values")
            for key in o.values.keys {
                #expect(o.tolerances[key] != nil,
                        "oracle '\(o.id)' value '\(key)' has no tolerance")
                #expect((o.tolerances[key] ?? 0) > 0,
                        "oracle '\(o.id)' tolerance '\(key)' must be positive")
            }
            for key in o.tolerances.keys {
                #expect(o.values[key] != nil,
                        "oracle '\(o.id)' tolerance '\(key)' has no value")
            }
        }
    }

    @Test func oracleIDsAreUnique() {
        let ids = Oracles.all.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate oracle id in the corpus")
    }

    @Test func requireResolvesEveryDeclaredID() {
        for o in Oracles.all {
            #expect(Oracles.require(o.id).id == o.id)
        }
    }

    /// The corpus must actually cover the bodies the app renders — otherwise a body could
    /// silently drift with nothing watching it. (This is the gap that existed before:
    /// Moon, Uranus, Neptune and Pluto had no external check at all.)
    @Test func everyRenderedBodyHasAnOracle() {
        for body in CelestialBody.allCases {
            let id = "horizons-\(body.rawValue)"
            #expect(Oracles.all.contains { $0.id == id },
                    "no oracle covers \(body.name) — add one before shipping")
        }
    }
}
