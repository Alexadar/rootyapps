import Foundation
import Combine
import InterferenceKit

@MainActor
final class InterferenceViewModel: ObservableObject {
    // Boundary (SBIR)
    @Published var distance = 0.6
    @Published var speed = 343.0
    @Published var reflectionGain = 0.0     // dB (≤0)
    @Published var targetHz = 200.0
    var notches: [Double] { Comb.boundaryNotches(distanceM: distance, speed: speed, count: 4) }
    var firstNotch: Double { notches.first ?? 0 }
    var firstPeak: Double { Comb.boundaryFirstPeak(distanceM: distance, speed: speed) }
    var suggestedDistance: Double { Comb.distanceForFirstNotchAbove(targetHz: targetHz, speed: speed) }
    var nullDepth: Double { Comb.nullDepthDB(reflectionGainDB: reflectionGain) }
    var peakGain: Double { Comb.peakGainDB(reflectionGainDB: reflectionGain) }

    // Two coherent sources
    @Published var pathDiff = 1.0
    var delayMs: Double { Comb.delayMs(pathDiffM: pathDiff, speed: speed) }
    var combSpacing: Double { Comb.combSpacing(pathDiffM: pathDiff, speed: speed) }
    var combFirstNull: Double { Comb.combFirstNull(pathDiffM: pathDiff, speed: speed) }
    var combNulls: [Double] { Comb.combNulls(pathDiffM: pathDiff, speed: speed, count: 4) }
}
