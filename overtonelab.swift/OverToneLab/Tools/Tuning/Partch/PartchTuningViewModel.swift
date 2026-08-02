import Foundation
import Combine
import PartchKit

@MainActor
final class PartchTuningViewModel: ObservableObject {
    // Interval tab — two pitches
    @Published var freqLow = 220.0
    @Published var freqHigh = 330.0
    @Published var limit = 15

    var ratio: Double { freqHigh / max(freqLow, 0.0001) }
    var cents: Double { Spectral.cents(ratio) }
    var just: (num: Int, den: Int, cents: Double) { Spectral.nearestJustRatio(cents: cents, oddLimit: limit) }
    var justError: Double { cents - just.cents }

    var nearestSemitone: Int { Int((cents / 100).rounded()) }
    var etDeviation: Double { cents - Double(nearestSemitone) * 100 }

    // Ratio tab — explicit fraction
    @Published var num = 3
    @Published var den = 2
    var ratioCents: Double { Spectral.cents(Double(num) / Double(max(den, 1))) }
    var tenney: Double { Spectral.tenneyHeight(num: num, den: den) }
    var ratioNearestSemitone: Int { Int((ratioCents / 100).rounded()) }
    var ratioEtDeviation: Double { ratioCents - Double(ratioNearestSemitone) * 100 }
}
