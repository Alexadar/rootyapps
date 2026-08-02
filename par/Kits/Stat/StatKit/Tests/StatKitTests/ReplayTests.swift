import Testing
import Foundation
import StatKit

/// The Kit-level half of the tape's correctness requirement (`par/plan_tape.md` §3): a saved tape stores
/// the data and the model, and re-fits on reopening. The observations must round-trip exactly — the fit
/// is a function of every digit of them — and a `Fit` restored from disk must be one this Kit could
/// actually have produced.
///
/// ORACLES:
///  • IDENTITY — encode/decode is the identity on `Model`, `Fit` and `Summary`; `fit` is pure.
///  • INVARIANT — corrupt persisted data throws a `DecodingError` rather than trapping.
@Suite("Tape replay — codability and determinism")
struct ReplayTests {

    @Test("published datasets replay to the identical fit", arguments: ["norris", "lew"])
    func replayIsBitForBit(dataset: String) throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()

        for model in Stat.Model.allCases {
            #expect(try decoder.decode(Stat.Model.self, from: encoder.encode(model)) == model)
        }

        // The data itself is what a tape stores; re-fitting decoded data must be bit-for-bit identical.
        let (sourceX, sourceY) = dataset == "norris"
            ? (Oracles.norrisX, Oracles.norrisY)
            : (Array(Oracles.lewValues.indices).map(Double.init), Oracles.lewValues)
        let x = try decoder.decode([Double].self, from: encoder.encode(sourceX))
        let y = try decoder.decode([Double].self, from: encoder.encode(sourceY))
        #expect(x == sourceX)
        #expect(y == sourceY)

        let before = try Stat.fit(x: sourceX, y: sourceY)
        let after = try Stat.fit(x: x, y: y)
        #expect(after == before, "\(dataset): the fit moved across a round trip")

        // And the fit and summary round-trip so a tape row can be drawn without re-deriving it.
        #expect(try decoder.decode(Stat.Fit.self, from: encoder.encode(before)) == before)
        let summary = Stat.summary(sourceY)
        #expect(try decoder.decode(Stat.Summary.self, from: encoder.encode(summary)) == summary)
    }

    @Test func fittingIsPureAndLeavesTheObservationsAlone() throws {
        let first = try Stat.fit(x: Oracles.norrisX, y: Oracles.norrisY)
        for _ in 0..<50 {
            #expect(try Stat.fit(x: Oracles.norrisX, y: Oracles.norrisY) == first)
        }
    }

    @Test func corruptPersistedFitsThrow() {
        let corrupt = [
            // two observations — `fit` requires three
            #"{"model":"linear","intercept":1,"slope":2,"interceptStandardDeviation":0.1,"slopeStandardDeviation":0.1,"residualStandardDeviation":0.1,"rSquared":0.9,"correlation":0.95,"count":2}"#,
            // a negative standard deviation
            #"{"model":"linear","intercept":1,"slope":2,"interceptStandardDeviation":-0.1,"slopeStandardDeviation":0.1,"residualStandardDeviation":0.1,"rSquared":0.9,"correlation":0.95,"count":10}"#,
            // r squared outside [0, 1]
            #"{"model":"linear","intercept":1,"slope":2,"interceptStandardDeviation":0.1,"slopeStandardDeviation":0.1,"residualStandardDeviation":0.1,"rSquared":1.4,"correlation":0.95,"count":10}"#,
            // a correlation of 9
            #"{"model":"linear","intercept":1,"slope":2,"interceptStandardDeviation":0.1,"slopeStandardDeviation":0.1,"residualStandardDeviation":0.1,"rSquared":0.9,"correlation":9,"count":10}"#,
            // a model this Kit does not implement
            #"{"model":"quadratic","intercept":1,"slope":2,"interceptStandardDeviation":0.1,"slopeStandardDeviation":0.1,"residualStandardDeviation":0.1,"rSquared":0.9,"correlation":0.95,"count":10}"#,
        ]
        for json in corrupt {
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode(Stat.Fit.self, from: Data(json.utf8))
            }
        }
        // A real fit is still accepted — the guard has to reject the impossible, not the merely tight.
        #expect(throws: Never.self) {
            let real = try Stat.fit(x: Oracles.norrisX, y: Oracles.norrisY)
            _ = try JSONDecoder().decode(Stat.Fit.self, from: JSONEncoder().encode(real))
        }
    }

    @Test func corruptPersistedSummariesThrow() {
        let corrupt = [
            #"{"count":0,"sum":0,"sumOfSquares":0,"mean":0,"sampleStandardDeviation":0,"populationStandardDeviation":0,"minimum":0,"maximum":0}"#,
            #"{"count":5,"sum":10,"sumOfSquares":30,"mean":2,"sampleStandardDeviation":-1,"populationStandardDeviation":1,"minimum":1,"maximum":3}"#,
            // the minimum above the maximum
            #"{"count":5,"sum":10,"sumOfSquares":30,"mean":2,"sampleStandardDeviation":1,"populationStandardDeviation":1,"minimum":9,"maximum":3}"#,
        ]
        for json in corrupt {
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode(Stat.Summary.self, from: Data(json.utf8))
            }
        }
    }
}
