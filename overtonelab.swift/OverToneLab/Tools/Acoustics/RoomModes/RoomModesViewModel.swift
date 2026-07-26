import Foundation
import Combine
import RoomModesKit

@MainActor
final class RoomModesViewModel: ObservableObject {
    @Published var length = 5.0
    @Published var width = 4.0
    @Published var height = 2.8
    @Published var speed = 343.0
    @Published var maxFreq = 300.0

    var modes: [RoomModes.Mode] { RoomModes.modes(lengthM: length, widthM: width, heightM: height, speed: speed, maxHz: maxFreq) }
    var modeCount: Int { modes.count }
    var smallestSpacing: Double { RoomModes.smallestSpacing(modes) }

    var normalized: (Double, Double, Double) { RoomModes.normalizedRatio(length, width, height) }
    var nearest: (name: String, mid: Double, long: Double, distance: Double) { RoomModes.nearestRatio(length, width, height) }
    var bonello: Bool { RoomModes.bonelloPasses(lengthM: length, widthM: width, heightM: height, speed: speed, upToHz: maxFreq) }
    var degenerate: Bool { RoomModes.hasDegenerateRatio(length, width, height) }
}
