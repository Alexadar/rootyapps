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
    var diffDB: Double {
        let r = valA != 0 ? valB / valA : 0
        return powerMode ? Levels.powerDB(ratio: r) : Levels.voltageDB(ratio: r)
    }

    // Dynamic range
    @Published var bits = 16.0
    var dynamicRange: Double { FileInfo.dynamicRangeDB(bitDepth: bits) }
}
