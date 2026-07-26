import Foundation
import Combine
import SPLKit

@MainActor
final class SPLViewModel: ObservableObject {
    // Distance
    @Published var spl1 = 100.0
    @Published var r1 = 1.0
    @Published var r2 = 4.0
    var splAtR2: Double { SPL.atDistance(spl1: spl1, from: r1, to: r2) }

    // Summation
    @Published var la = 90.0
    @Published var lb = 85.0
    var sumTwo: Double { SPL.sumIncoherent([la, lb]) }
    @Published var level = 90.0
    @Published var count = 4
    var incN: Double { SPL.sumIncoherent(Array(repeating: level, count: count)) }
    var cohN: Double { SPL.sumCoherent(level: level, count: count) }
}
