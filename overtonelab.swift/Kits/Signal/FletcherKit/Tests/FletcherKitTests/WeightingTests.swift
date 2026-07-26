import Testing
import Foundation
@testable import FletcherKit

struct Oracle {
    let id, source: String
    let values: [Double: Double]   // frequency → expected dB
    let tol: Double
}
enum Oracles {
    static let all: [Oracle] = [
        Oracle(id: "iec61672-A",
               source: "IEC 61672-1 A-weighting table: 1 kHz = 0.0 dB (def.), 100 Hz = −19.1, 10 kHz = −2.5, 20 Hz = −50.5",
               values: [1000: 0.0, 100: -19.1, 10000: -2.5, 20: -50.5], tol: 0.3),
    ]
}

@Suite("Oracle corpus integrity")
struct GuardTests {
    @Test func hasSources() { for o in Oracles.all { #expect(!o.source.isEmpty); #expect(!o.values.isEmpty) } }
}

// ORACLE-BACKED: IEC 61672 published A-weighting values.
@Suite("A-weighting vs IEC 61672")
struct WeightingTests {
    @Test func aWeightingMatchesIEC() {
        let o = Oracles.all[0]
        for (f, expected) in o.values {
            let a = Weighting.aWeightingDB(f)
            #expect(abs(a - expected) <= o.tol, "A(\(f))=\(a), expected \(expected) ±\(o.tol) [\(o.source)]")
        }
    }
    @Test func cAndZReference() {
        #expect(abs(Weighting.cWeightingDB(1000) - 0) < 0.1)   // C ≈ 0 dB at 1 kHz
        #expect(Weighting.zWeightingDB(50) == 0)
    }
}
