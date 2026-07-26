import Foundation
import Combine
import CommaKit

@MainActor
final class CommaTuningViewModel: ObservableObject {
    // EDO
    @Published var edoN = 12.0
    var edoSteps: [Double] { Tuning.edo(max(1, Int(edoN))) }
    var edoStepSize: Double { 1200 / max(1, edoN) }

    // Interval ↔ cents
    @Published var ratioNum = 3.0
    @Published var ratioDen = 2.0
    @Published var centsInput = 700.0
    var ratioCents: Double { Tuning.cents(ratio: ratioNum / max(ratioDen, 1e-9)) }
    var centsAsRatio: Double { pow(2, centsInput / 1200) }

    // Named intervals / commas (published values)
    var justFifth: Double { Tuning.justFifthCents }
    var meantoneFifth: Double { Tuning.quarterCommaMeantoneFifthCents }
    var syntonicComma: Double { Tuning.syntonicCommaCents }
    var pythagoreanComma: Double { Tuning.pythagoreanCommaCents }
}
