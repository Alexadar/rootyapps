import Foundation
import Combine
import MersenneKit

@MainActor
final class StringsViewModel: ObservableObject {
    // Tension (SI)
    @Published var freq = 110.0
    @Published var lengthM = 0.65
    @Published var mu = 0.005
    var tensionN: Double { Strings.tensionN(frequencyHz: freq, lengthM: lengthM, linearDensityKgPerM: mu) }
    var tensionLbf: Double { tensionN / 4.4482216 }

    // Frets
    @Published var scaleIn = 25.5
    @Published var frets = 12.0
    var fretPositions: [(fret: Int, distance: Double)] {
        (1...max(1, Int(frets))).map { ($0, Strings.fretDistance(scale: scaleIn, fret: $0)) }
    }
}
