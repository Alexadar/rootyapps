import Foundation
import StatKit

/// A ground-truth entry transcribed from an EXTERNAL published authority.
/// The implementer must NOT invent these numbers — every entry cites its `source`.
/// Policy: ../../../../../calculators/VALIDATION.md · ledger: par/scratch/SOURCES.md
struct Oracle {
    let id: String
    let source: String
    let inputs: [String: Double]
    let precision: String
    let values: [String: Double]
    let tolerances: [String: Double]

    /// Relative comparison: NIST certifies 15 significant digits, so a relative tolerance is the honest
    /// test for values spanning 1e-3 to 1e6.
    func matches(_ key: String, _ actual: Double) -> Bool {
        guard let v = values[key], let t = tolerances[key] else { return false }
        return abs(actual - v) <= t * Swift.max(abs(v), 1)
    }

    func input(_ key: String) -> Double {
        guard let v = inputs[key] else { fatalError("oracle '\(id)' has no input '\(key)'") }
        return v
    }

    func value(_ key: String) -> Double {
        guard let v = values[key] else { fatalError("oracle '\(id)' has no value '\(key)'") }
        return v
    }
}

enum Oracles {
    static let numAcc2Source = """
        NIST/ITL Statistical Reference Datasets, NumAcc2 (univariate summary statistics, 1001 \
        observations constructed so that the mean is exactly 1.2, the sample standard deviation exactly \
        0.1 and the lag-1 autocorrelation exactly -0.999); \
        https://www.itl.nist.gov/div898/strd/univ/data/NumAcc2.dat (US government work, public domain); \
        retrieved 2026-07-27. NIST publishes this dataset specifically to expose the catastrophic \
        cancellation in the textbook variance formula.
        """

    /// NumAcc2's data is generated rather than transcribed, because NIST *defines* it by construction:
    /// 1.2 followed by alternating 1.1 and 1.3, 1001 values in total. Building it here is the honest
    /// transcription of that definition, and the certified values below are exact.
    static var numAcc2Values: [Double] {
        var values: [Double] = [1.2]
        for index in 1..<1001 { values.append(index % 2 == 1 ? 1.1 : 1.3) }
        return values
    }

    static let numAcc2Row = Oracle(
        id: "nist-strd-numacc2",
        source: numAcc2Source,
        inputs: ["observations": 1001],
        precision: "±1e-12 relative — NIST states these certified values are exact, so the only error "
            + "allowed is the floating-point summation of exactly-representable-in-decimal inputs",
        values: ["mean": 1.2, "sampleStandardDeviation": 0.1, "autocorrelationLag1": -0.999],
        tolerances: ["mean": 1e-12, "sampleStandardDeviation": 1e-12, "autocorrelationLag1": 1e-12]
    )

    /// The corpus. Expected numbers live ONLY here, each tied to an external source.
    static let all: [Oracle] = nistRows + [numAcc2Row]

    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else {
            fatalError("unknown oracle id '\(id)'")
        }
        return o
    }
}
