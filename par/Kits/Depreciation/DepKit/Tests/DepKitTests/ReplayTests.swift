import Testing
import Foundation
import DepKit

/// The Kit-level half of the tape's correctness requirement (`par/plan_tape.md` §3): a saved tape stores
/// the asset, method and convention, and rebuilds the schedule on reopening. All three must round-trip
/// exactly — the convention and the rounding policy select different published columns, so losing either
/// would silently restate a tax deduction.
///
/// ORACLES:
///  • IDENTITY — encode/decode is the identity on `Asset`, `Method`, `Convention` and `Rounding`;
///    `schedule` is pure.
///  • INVARIANT — corrupt persisted assets throw rather than trapping.
@Suite("Tape replay — codability and determinism")
struct ReplayTests {

    static let assets: [Depreciation.Asset] = [
        .init(cost: 10_000, recoveryYears: 7),
        .init(cost: 50_000, salvage: 5_000, recoveryYears: 10),
        .init(cost: 1_234.56, salvage: 123.45, recoveryYears: 5, factor: 1.5),
    ]

    @Test("assets and schedules replay identically", arguments: assets.indices)
    func replayIsBitForBit(index: Int) throws {
        let original = Self.assets[index]
        let restored = try JSONDecoder().decode(
            Depreciation.Asset.self, from: JSONEncoder().encode(original)
        )
        #expect(restored == original)

        for method in Depreciation.Method.allCases where !(method == .macrsGDS && original.salvage != 0) {
            for convention in Depreciation.Convention.allCases {
                #expect(Depreciation.schedule(restored, method: method, convention: convention)
                        == Depreciation.schedule(original, method: method, convention: convention),
                        "\(method.rawValue)/\(convention.rawValue) changed after a round trip")
            }
        }
    }

    @Test func methodConventionAndRoundingRoundTrip() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        for method in Depreciation.Method.allCases {
            #expect(try decoder.decode(Depreciation.Method.self, from: encoder.encode(method)) == method)
        }
        for convention in Depreciation.Convention.allCases {
            #expect(try decoder.decode(Depreciation.Convention.self,
                                       from: encoder.encode(convention)) == convention)
        }
        for rounding: Depreciation.Rounding in [.exact, .irsTable(decimals: 2), .irsTable(decimals: 3)] {
            let restored = try decoder.decode(Depreciation.Rounding.self,
                                              from: encoder.encode(rounding))
            #expect(restored == rounding, "the rounding policy selects a different published column")
        }
    }

    @Test func corruptPersistedAssetsThrow() {
        let corrupt = [
            #"{"cost":0,"salvage":0,"recoveryYears":7,"factor":2}"#,
            #"{"cost":-100,"salvage":0,"recoveryYears":7,"factor":2}"#,
            #"{"cost":100,"salvage":200,"recoveryYears":7,"factor":2}"#,
            #"{"cost":100,"salvage":-1,"recoveryYears":7,"factor":2}"#,
            #"{"cost":100,"salvage":0,"recoveryYears":0,"factor":2}"#,
            #"{"cost":100,"salvage":0,"recoveryYears":7,"factor":0}"#,
        ]
        for json in corrupt {
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode(Depreciation.Asset.self, from: Data(json.utf8))
            }
        }
    }
}
