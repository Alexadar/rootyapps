import Foundation
import Combine
import SabineKit

@MainActor
final class RoomViewModel: ObservableObject {
    // Reverb
    @Published var volume = 200.0
    @Published var absorption = 40.0     // sabins (Σ Sα)
    @Published var surface = 240.0       // m²
    @Published var avgAbsorption = 0.17
    var sabineRT60: Double { Acoustics.sabineRT60(volumeM3: volume, absorptionSabins: absorption) }
    var eyringRT60: Double { Acoustics.eyringRT60(volumeM3: volume, surfaceM2: surface, avgAbsorption: avgAbsorption) }
    var schroeder: Double { Acoustics.schroederHz(rt60: sabineRT60, volumeM3: volume) }

    // Modes
    @Published var length = 6.0
    @Published var width = 4.5
    @Published var height = 2.8
    var axialModes: [(name: String, freqs: [Double])] {
        [("Length", modes(length)), ("Width", modes(width)), ("Height", modes(height))]
    }
    private func modes(_ L: Double) -> [Double] { (1...3).map { Acoustics.axialModeHz(lengthM: L, order: $0) } }
}
