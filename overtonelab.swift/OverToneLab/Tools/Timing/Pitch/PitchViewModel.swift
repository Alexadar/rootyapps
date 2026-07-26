import Foundation
import Combine
import PitchKit

@MainActor
final class PitchViewModel: ObservableObject {
    // Note ↔ frequency
    @Published var midi = 69
    var noteName: String { Pitch.noteName(midi: midi) }
    var noteHz: Double { Pitch.noteToHz(midi: Double(midi)) }
    var wavelengthM: Double { Pitch.wavelengthM(hz: noteHz) }
    @Published var freqInput = 440.0
    var nearestNote: String { Pitch.noteName(midi: Int(Pitch.hzToNote(freqInput).rounded())) }
    var centsOff: Double { let n = Pitch.hzToNote(freqInput); return (n - n.rounded()) * 100 }

    // Harmonics
    @Published var fundamental = 110.0
    var harmonics: [(n: Int, hz: Double, cents: Double)] {
        (1...8).map { ($0, Harmonics.harmonicHz(fundamental: fundamental, n: $0), Harmonics.centsFromET(n: $0)) }
    }

    // Beats
    @Published var f1 = 440.0
    @Published var f2 = 443.0
    var beatHz: Double { Beats.beatHz(f1, f2) }
    var beatCents: Double { Pitch.centsBetween(f1, f2) }

    // Doppler
    @Published var sourceHz = 1000.0
    @Published var vSource = 30.0
    @Published var vObserver = 0.0
    var observedHz: Double { Doppler.observedHz(source: sourceHz, vSource: vSource, vObserver: vObserver) }
    var shiftCents: Double { Pitch.centsBetween(sourceHz, observedHz) }
}
