import Foundation
import Combine
import DynamicsKit

@MainActor
final class CompressorViewModel: ObservableObject {
    // Gain computer
    @Published var input = -10.0
    @Published var threshold = -20.0
    @Published var ratio = 4.0
    @Published var knee = 6.0
    @Published var makeup = 0.0
    var gainReduction: Double { Compressor.gainReductionDB(inputDB: input, thresholdDB: threshold, ratio: ratio, kneeDB: knee) }
    var output: Double { Compressor.outputLevelDB(inputDB: input, thresholdDB: threshold, ratio: ratio, kneeDB: knee, makeupDB: makeup) }
    var effRatio: Double { Compressor.effectiveRatio(inputDB: input, thresholdDB: threshold, ratio: ratio, kneeDB: knee) }

    // Time constants
    @Published var time = 10.0
    @Published var fs = 48000.0
    var tau: Double { Compressor.timeConstantMs(riseTimeMs: time) }
    var coeff: Double { Compressor.onePoleCoeff(riseTimeMs: time, fs: fs) }
    var pctAtTime: Double { Compressor.percentReached(afterMs: time, riseTimeMs: time) }
}
