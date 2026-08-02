import Foundation
import Testing
import TVMKit
@testable import Par

/// The screen shipped able to solve only for PMT.
///
/// `TVMKit.solve(for:)` has always handled all five registers, but nothing in the UI ever assigned
/// `solveFor`, so four fifths of the screen's stated purpose was unreachable — and the App Store
/// description promising "any of n, i, PV, PMT or FV" was, for that build, untrue. These tests exist
/// so it cannot silently become untrue again.
@MainActor
@Suite("TVM — solving for any of the five")
struct SolveTargetTests {

    @Test func everyRegisterCanBecomeTheAnswer() {
        for target in [TVM.Variable.periods, .ratePct, .presentValue, .payment, .futureValue] {
            let model = TVMViewModel()
            // A set of registers that has a real answer whichever one is withheld.
            model.periods = 360
            model.annualRatePct = 6.25
            model.presentValue = 420_000
            model.payment = -2_586.01
            model.futureValue = 0

            model.solve(for: target)
            #expect(model.solveFor == target,
                    Comment(rawValue: "solve target did not move to \(target.rawValue)"))
            #expect(model.tapeRow() != nil,
                    Comment(rawValue: "solving for \(target.rawValue) produced nothing to append"))
        }
    }

    @Test func theAnswerIsNeverTheRegisterBeingTypedInto() {
        let model = TVMViewModel()
        model.select(.presentValue)
        #expect(model.entryTarget == .presentValue)

        // Making PV the answer has to move the keypad somewhere else, or the next keystroke would
        // overwrite the number the app just computed.
        model.solve(for: .presentValue)
        #expect(model.solveFor == .presentValue)
        #expect(model.entryTarget != .presentValue)
    }

    @Test func aPendingEntryIsDiscardedWhenItsRegisterBecomesTheAnswer() {
        let model = TVMViewModel()
        model.select(.futureValue)
        model.digit(5)
        #expect(model.entryBuffer == "5")

        model.solve(for: .futureValue)
        #expect(model.entryBuffer == nil, "half-typed digits must not follow the keypad to a new register")
    }

    @Test func reSelectingTheCurrentTargetChangesNothing() {
        let model = TVMViewModel()
        model.select(.presentValue)
        model.digit(7)
        model.solve(for: model.solveFor)          // PMT is already the target
        #expect(model.entryTarget == .presentValue)
        #expect(model.entryBuffer == "7")
    }

    @Test func clearEntryLeavesTheRegisterAloneUntilADigitArrives() {
        let model = TVMViewModel()
        model.select(.periods)
        model.clearEntry()
        // Committing an empty buffer as zero used to push n = 0 through the solver, so clearing a
        // field made the screen report that no rate balances the cash flows.
        #expect(model.periods == 360)
        model.digit(1)
        #expect(model.periods == 1)
    }
}
