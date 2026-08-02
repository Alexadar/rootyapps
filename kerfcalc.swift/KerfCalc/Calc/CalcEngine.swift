import Foundation
import DimensionKit

/// Thin `ObservableObject` wrapper around the unit-tested `TapeCalc` state machine (DimensionKit).
/// All arithmetic, key-routing, and the CM-Pro register solves live in `TapeCalc` (see
/// TapeCalcTests); this layer only republishes `display`/`tape`/`rise`/`run` for SwiftUI.
@MainActor
final class CalcEngine: ObservableObject {
    typealias Op = TapeCalc.Op

    @Published private(set) var display: String = "0\""
    @Published private(set) var tape: String = ""
    @Published private(set) var rise: String? = nil
    @Published private(set) var run: String? = nil
    @Published var denominator: Int64 = 16

    private var calc = TapeCalc()

    /// The current readout as an exact `FeetInch` — what a field editor commits on Done.
    var currentValue: FeetInch { calc.displayValue }
    /// Seed the readout with an existing value for editing.
    func preload(_ v: FeetInch) { calc.preload(v); sync() }

    private func sync() {
        display = calc.display; tape = calc.tape
        rise = calc.riseDisplay; run = calc.runDisplay
        denominator = calc.denominator
    }

    func digit(_ d: Int) { calc.digit(d); sync() }
    func feetKey() { calc.feetKey(); sync() }
    func inchKey() { calc.inchKey(); sync() }
    func fractionKey() { calc.fractionKey(); sync() }
    func setOp(_ o: Op) { calc.setOp(o); sync() }
    func equals() { calc.equals(); sync() }
    func clear() { calc.clear(); sync() }
    func backspace() { calc.backspace(); sync() }
    func convert(to unit: LengthUnit) { calc.convert(to: unit); sync() }
    func setDenominator(_ d: Int64) { calc.setDenominator(d); sync() }

    // CM-Pro right-triangle keys
    func storeRise() { calc.storeRise(); sync() }
    func storeRun() { calc.storeRun(); sync() }
    func solveDiagonal() { calc.solveDiagonal(); sync() }
    func solvePitch() { calc.solvePitch(); sync() }
}
