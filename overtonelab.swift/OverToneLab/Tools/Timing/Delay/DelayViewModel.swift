import Foundation
import Combine
import TimingKit

@MainActor
final class DelayViewModel: ObservableObject {
    // Tempo-synced delay
    @Published var bpm = 120.0
    @Published var division = 8.0
    @Published var dotted = false
    @Published var triplet = false
    var delayMs: Double { Delay.noteDelayMs(bpm: bpm, division: division, dotted: dotted, triplet: triplet) }
    var delayHz: Double { Delay.rateHz(ms: delayMs) }
    var table: [(name: String, straight: Double, dotted: Double, triplet: Double)] {
        [(4, "1/4"), (8, "1/8"), (16, "1/16")].map { d in
            (d.1,
             Delay.noteDelayMs(bpm: bpm, division: Double(d.0)),
             Delay.noteDelayMs(bpm: bpm, division: Double(d.0), dotted: true),
             Delay.noteDelayMs(bpm: bpm, division: Double(d.0), triplet: true))
        }
    }

    // Distance / alignment
    @Published var meters = 3.43
    var distanceMs: Double { Delay.distanceMs(meters: meters) }
    var withinHaas: Bool { distanceMs <= Delay.haasFusionMaxMs }

    // Comb filter
    @Published var combDelayMs = 1.0
    var combNullHz: Double { Delay.combFirstNullHz(delayMs: combDelayMs) }
}
