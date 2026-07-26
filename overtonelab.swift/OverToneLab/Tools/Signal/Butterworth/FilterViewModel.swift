import Foundation
import Combine
import ButterworthKit

@MainActor
final class FilterViewModel: ObservableObject {
    // Filter tab
    @Published var fcHz = 1000.0
    @Published var order = 4
    @Published var testHz = 2000.0

    var ratio: Double { testHz / max(fcHz, 0.0001) }
    var magDB: Double { Filters.butterworthDB(order: order, ratio: ratio) }
    var slopeDbOct: Double { Double(order) * 6 }

    var response: [(label: String, db: Double)] {
        [-2, -1, 0, 1, 2].map { oct in
            let r = pow(2.0, Double(oct))
            let name = oct == 0 ? "fc" : (oct > 0 ? "+\(oct) oct" : "\(oct) oct")
            return (name, Filters.butterworthDB(order: order, ratio: r))
        }
    }

    // Crossover tab — LR order = 2·butterworthOrder
    @Published var lrHalf = 2   // butterworth half-order: 1→LR2, 2→LR4, 4→LR8
    @Published var xoverHz = 2500.0
    var lrName: String { "LR\(lrHalf * 2)" }
    var lrBranchAtFcDB: Double { Filters.linkwitzRileyDB(butterworthOrder: lrHalf, ratio: 1) }
    var lrSlopeDbOct: Double { Double(lrHalf * 2) * 6 }
    var lrOctaveAwayDB: Double { Filters.linkwitzRileyDB(butterworthOrder: lrHalf, ratio: 2) }
}
