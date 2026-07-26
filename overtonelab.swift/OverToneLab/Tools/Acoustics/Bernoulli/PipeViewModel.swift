import Foundation
import Combine
import BernoulliKit

@MainActor
final class PipeViewModel: ObservableObject {
    @Published var lengthM = 0.5
    @Published var isOpen = true
    @Published var radiusMm = 20.0

    private func f(_ n: Int) -> Double {
        isOpen ? Pipes.openPipeHz(lengthM: lengthM, harmonic: n) : Pipes.closedPipeHz(lengthM: lengthM, harmonic: n)
    }
    var fundamental: Double { f(1) }
    var harmonics: [(index: Int, hz: Double)] { (1...6).map { ($0, f($0)) } }

    var endFlangedMm: Double { Pipes.endCorrectionM(radiusM: radiusMm / 1000, flanged: true) * 1000 }
    var endUnflangedMm: Double { Pipes.endCorrectionM(radiusM: radiusMm / 1000, flanged: false) * 1000 }
}
