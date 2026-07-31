import Foundation
import Combine
import AudioUtilKit

@MainActor
final class LevelsViewModel: ObservableObject {
    // dB convert
    @Published var volts = 1.0
    var dBu: Double { Levels.voltsToDBu(volts) }
    var dBV: Double { Levels.voltsToDBV(volts) }

    // Compare
    @Published var valA = 1.0
    @Published var valB = 2.0
    @Published var powerMode = false
    /// The guard has to cover the LOGARITHM, not just the division.
    ///
    /// The old form guarded `valA != 0` and then handed the resulting `0` to `log10`, which is −∞ —
    /// so a zero reference produced a literal "−∞ dB" rather than a refusal. Unreachable through the
    /// UI today only by luck: `NumberField` clamps this field to 0.0001…1000000, so nothing on screen
    /// changes and no screenshot is invalidated. That clamp is a display-layer accident, though, and
    /// the model should not depend on it.
    var diffDB: Double {
        guard valA > 0, valB > 0 else { return 0 }
        return powerMode ? Levels.powerDB(ratio: valB / valA) : Levels.voltageDB(ratio: valB / valA)
    }

    // Dynamic range
    @Published var bits = 16.0
    var dynamicRange: Double { FileInfo.dynamicRangeDB(bitDepth: bits) }
}
