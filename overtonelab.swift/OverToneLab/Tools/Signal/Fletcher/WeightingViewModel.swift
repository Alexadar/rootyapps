import Foundation
import Combine
import FletcherKit

@MainActor
final class WeightingViewModel: ObservableObject {
    @Published var freq = 1000.0
    var aWeight: Double { Weighting.aWeightingDB(freq) }
    var cWeight: Double { Weighting.cWeightingDB(freq) }
    var zWeight: Double { Weighting.zWeightingDB(freq) }

    let bands: [Double] = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    var bandTable: [(hz: Double, a: Double)] { bands.map { ($0, Weighting.aWeightingDB($0)) } }
}
