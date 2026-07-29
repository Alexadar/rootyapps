import Testing
import Foundation
import TVMKit

/// The Kit-level half of the tape's correctness requirement (`par/plan_tape.md` §3).
///
/// A tape stores the *inputs* of every solved problem and re-derives the result when the document is
/// reopened — it never persists a number it cannot re-compute. That makes two properties of this Kit
/// load-bearing, and neither is free:
///
///  1. **Lossless codability.** Registers must survive a JSON round trip exactly, including doubles.
///  2. **Bit-for-bit determinism.** The same registers must produce the identical `Double`, not merely
///     one within a tolerance — the tape test in the app target compares stored against re-solved with
///     `==`, and the incumbent Par is displacing is the one whose "stored registers will 0 out for no
///     reason whatsoever".
///
/// The tape's own tests (append/reopen, edit-one-line, 1,000 entries, disk round trip) belong to the app
/// target. What lives here is the guarantee they rest on.
///
/// ORACLES:
///  • IDENTITY — encode/decode is the identity on `Registers`; `solve` is a pure function of them.
///  • INVARIANT — corrupt persisted data throws a `DecodingError` rather than trapping.
@Suite("Tape replay — codability and determinism")
struct ReplayTests {

    static let registers: [TVM.Registers] = [
        .init(periods: 360, annualRatePct: 6.25, presentValue: 420_000, futureValue: 0,
              paymentsPerYear: 12, compoundsPerYear: 12),
        .init(periods: 180, annualRatePct: 5.75, presentValue: 420_000, futureValue: 0,
              paymentsPerYear: 12, compoundsPerYear: 12),
        .init(periods: 300, annualRatePct: 5.25, presentValue: 250_000, payment: -1480,
              paymentsPerYear: 12, compoundsPerYear: 2, timing: .begin),
        .init(periods: 24, annualRatePct: 0, presentValue: 5_000, payment: -208.33,
              paymentsPerYear: 12, compoundsPerYear: 12),
        // Values chosen to have no exact binary representation: the round trip has to be real.
        .init(periods: 37, annualRatePct: 4.9366666666666665, presentValue: 12_345.67,
              payment: -333.331, futureValue: 1_111.111, paymentsPerYear: 26, compoundsPerYear: 4),
    ]

    @Test("registers survive a JSON round trip exactly", arguments: registers.indices)
    func codableRoundTripIsLossless(index: Int) throws {
        let original = Self.registers[index]
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(TVM.Registers.self, from: data)

        #expect(restored == original, "a reopened tape must hold the registers it was saved with")
        // Field by field, with `==` on the doubles — not a tolerance. This is the property the tape's
        // "re-solve equals the stored result, bit-for-bit" claim depends on.
        #expect(restored.periods == original.periods)
        #expect(restored.annualRatePct == original.annualRatePct)
        #expect(restored.presentValue == original.presentValue)
        #expect(restored.payment == original.payment)
        #expect(restored.futureValue == original.futureValue)
        #expect(restored.paymentsPerYear == original.paymentsPerYear)
        #expect(restored.compoundsPerYear == original.compoundsPerYear)
        #expect(restored.timing == original.timing)
    }

    @Test("re-solving decoded registers reproduces the result bit-for-bit",
          arguments: registers.indices)
    func replayIsBitForBit(index: Int) throws {
        let original = Self.registers[index]

        for variable in TVM.Variable.allCases {
            // Skip the registers this case cannot solve for (a zero-rate case has no rate to find).
            guard let solvedNow = try? TVM.solve(for: variable, original) else { continue }

            let data = try JSONEncoder().encode(original)
            let restored = try JSONDecoder().decode(TVM.Registers.self, from: data)
            let solvedAfterReopen = try TVM.solve(for: variable, restored)

            #expect(solvedAfterReopen == solvedNow,
                    "\(variable.rawValue): \(solvedAfterReopen) != \(solvedNow) after a round trip")
        }
    }

    /// Solving is pure: the same registers give the same answer every time, and solving one register
    /// does not disturb the others. A tape of independent lines depends on both.
    @Test func solvingIsPureAndLeavesTheInputsAlone() throws {
        let registers = Self.registers[0]
        let first = try TVM.solve(for: .payment, registers)
        for _ in 0..<100 {
            #expect(try TVM.solve(for: .payment, registers) == first)
        }
        // `Registers` is a value type, so the caller's copy cannot have moved.
        #expect(registers == Self.registers[0])

        // Editing one line's inputs must not change what another line solves to — the second of the
        // tape's four testable claims, at the level where it is actually guaranteed.
        let edited = registers.setting(.ratePct, to: 7.5)
        #expect(try TVM.solve(for: .payment, edited) != first)
        #expect(try TVM.solve(for: .payment, registers) == first)
    }

    /// Corrupt persisted data must throw, not trap. A tape file can be truncated, hand-edited or
    /// written by an older build; a `precondition` failure there would take the app down with it.
    @Test func corruptPersistedRegistersThrow() throws {
        let valid = try JSONEncoder().encode(Self.registers[0])
        #expect(throws: Never.self) { _ = try JSONDecoder().decode(TVM.Registers.self, from: valid) }

        let corrupt: [String] = [
            // negative term
            #"{"periods":-5,"annualRatePct":6,"presentValue":1000,"payment":0,"futureValue":0,"paymentsPerYear":12,"compoundsPerYear":12,"timing":"end"}"#,
            // zero payment frequency
            #"{"periods":12,"annualRatePct":6,"presentValue":1000,"payment":0,"futureValue":0,"paymentsPerYear":0,"compoundsPerYear":12,"timing":"end"}"#,
            // negative compounding frequency
            #"{"periods":12,"annualRatePct":6,"presentValue":1000,"payment":0,"futureValue":0,"paymentsPerYear":12,"compoundsPerYear":-1,"timing":"end"}"#,
            // unknown timing
            #"{"periods":12,"annualRatePct":6,"presentValue":1000,"payment":0,"futureValue":0,"paymentsPerYear":12,"compoundsPerYear":12,"timing":"sideways"}"#,
            // missing field
            #"{"periods":12,"annualRatePct":6,"presentValue":1000,"paymentsPerYear":12,"compoundsPerYear":12,"timing":"end"}"#,
        ]
        for json in corrupt {
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode(TVM.Registers.self, from: Data(json.utf8))
            }
        }
    }
}
