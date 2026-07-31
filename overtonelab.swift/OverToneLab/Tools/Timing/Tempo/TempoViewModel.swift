import Foundation
import Combine
import TimingKit

@MainActor
final class TempoViewModel: ObservableObject {
    // Note length
    @Published var bpm = 120.0
    @Published var division = 4.0
    @Published var dotted = false
    @Published var triplet = false

    // Reel demo: when OVERTONELAB_DEMO is set, sweep the tempo so every value recomputes live
    // (used only for capturing app-preview footage; no effect in the shipping app).
    private var demoTimer: Timer?
    private var demoPhase = 0.0
    init() {
        guard LaunchOverride.isSet("OVERTONELAB_DEMO") else { return }
        demoTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.demoPhase += 0.045
                self.bpm = (126 + 46 * sin(self.demoPhase)).rounded()   // ~80 … 172 BPM
            }
        }
    }
    var noteMs: Double { Tempo.noteMs(bpm: bpm, division: division, dotted: dotted, triplet: triplet) }
    var noteHz: Double { noteMs > 0 ? 1000 / noteMs : 0 }
    var subdivisionTable: [(name: String, ms: Double)] {
        [(1, "1/1"), (2, "1/2"), (4, "1/4"), (8, "1/8"), (16, "1/16")].map {
            ($0.1, Tempo.noteMs(bpm: bpm, division: Double($0.0)))
        }
    }

    // Tempo / bar
    @Published var beats = 4
    @Published var beatUnit = 4.0
    var beatMs: Double { Tempo.beatMs(bpm: bpm) }
    var barMs: Double { Tempo.barMs(bpm: bpm, beats: beats, beatUnit: beatUnit) }

    // Samples
    @Published var sampleRate = 48000.0
    @Published var timeMs = 500.0
    var samples: Double { Tempo.msToSamples(ms: timeMs, sampleRate: sampleRate) }

    // Varispeed
    @Published var semitones = 0.0
    var rateRatio: Double { Tempo.rateRatio(semitones: semitones) }
    var ratePercent: Double { (rateRatio - 1) * 100 }
}
