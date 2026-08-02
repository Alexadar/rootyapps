import Foundation
import Combine
import BenchmarkKit

@MainActor
final class LoudnessViewModel: ObservableObject {
    // Tone measurement — proves the BS.1770 engine on a known signal.
    @Published var toneHz = 1000.0
    @Published var toneDbfs = -20.0

    var measuredLUFS: Double {
        let sr = 48000.0
        let amp = pow(10, toneDbfs / 20)
        let n = Int(sr * 1.0)
        var ch = [Double](repeating: 0, count: n)
        let w = 2 * Double.pi * toneHz / sr
        for i in 0..<n { ch[i] = amp * sin(w * Double(i)) }
        return Loudness.integratedLUFS(channels: [ch, ch], sampleRate: sr)
    }

    // Target / normalization
    enum Platform: String, CaseIterable, Identifiable {
        case spotify = "Spotify", appleMusic = "Apple Music", youtube = "YouTube", ebu = "EBU R128", club = "Club/CD"
        var id: String { rawValue }
        var target: Double {
            switch self {
            case .spotify: return -14
            case .appleMusic: return -16
            case .youtube: return -14
            case .ebu: return -23
            case .club: return -9
            }
        }
    }
    @Published var measuredInput = -9.0
    @Published var platform: Platform = .spotify
    var gain: Double { platform.target - measuredInput }
}
