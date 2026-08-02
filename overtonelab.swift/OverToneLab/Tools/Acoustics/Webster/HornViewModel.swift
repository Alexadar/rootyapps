import Foundation
import Combine
import WebsterKit

@MainActor
final class HornViewModel: ObservableObject {
    // Exponential horn
    @Published var throatDiaCm = 2.5
    @Published var mouthDiaCm = 40.0
    @Published var lengthCm = 60.0

    private func areaFromDiaCm(_ d: Double) -> Double { .pi * pow(d / 100 / 2, 2) }
    var throatArea: Double { areaFromDiaCm(throatDiaCm) }
    var mouthArea: Double { areaFromDiaCm(mouthDiaCm) }
    var flareM: Double {
        let L = lengthCm / 100
        guard L > 0, throatArea > 0 else { return 0 }
        return log(mouthArea / throatArea) / L
    }
    var cutoffHz: Double { Horns.expHornCutoffHz(flareConstant: flareM) }
    var mouthAreaCheck: Double { Horns.expHornArea(mouthOrThroatA0: throatArea, flareConstant: flareM, x: lengthCm / 100) }

    // Helmholtz resonator
    @Published var neckDiaCm = 5.0
    @Published var cavityLiters = 20.0
    @Published var neckLenCm = 10.0
    private var neckArea: Double { areaFromDiaCm(neckDiaCm) }
    private var neckRadiusM: Double { neckDiaCm / 100 / 2 }
    /// Effective neck length adds a one-sided end correction (≈0.85·r for a flanged opening).
    var effLenM: Double { neckLenCm / 100 + 0.85 * neckRadiusM }
    var helmholtzHz: Double {
        Horns.helmholtzHz(neckAreaM2: neckArea, cavityVolumeM3: cavityLiters / 1000, neckLengthM: effLenM)
    }
}
