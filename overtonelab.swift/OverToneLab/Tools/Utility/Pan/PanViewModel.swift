import Foundation
import Combine
import AudioUtilKit

@MainActor
final class PanViewModel: ObservableObject {
    @Published var position = 0.0
    @Published var lawIndex = 0

    private let laws: [Pan.Law] = [.equalPower3dB, .linear6dB, .compromise45dB]
    var law: Pan.Law { laws[lawIndex] }

    private var gains: (left: Double, right: Double) { Pan.gains(position: position, law: law) }
    var leftDB: Double { 20 * log10(max(gains.left, 1e-9)) }
    var rightDB: Double { 20 * log10(max(gains.right, 1e-9)) }
    var centerDrop: Double { Pan.centerDropDB(law: law) }
}
