import Foundation
import Combine
import AirAbsorptionKit

@MainActor
final class AirAbsorptionViewModel: ObservableObject {
    @Published var temp = 20.0
    @Published var humidity = 50.0
    @Published var pressure = 101.325
    @Published var distance = 100.0
    @Published var freq = 1000.0

    var speed: Double { Atmosphere.speedOfSound(tempC: temp) }
    var alphaPerKm: Double { Atmosphere.absorptionDBPerKm(freqHz: freq, tempC: temp, humidityPct: humidity, pressureKPa: pressure) }
    var alphaPerM: Double { Atmosphere.absorptionDBPerM(freqHz: freq, tempC: temp, humidityPct: humidity, pressureKPa: pressure) }
    var loss: Double { Atmosphere.lossDB(freqHz: freq, tempC: temp, humidityPct: humidity, distanceM: distance, pressureKPa: pressure) }

    var bands: [(hz: Double, perKm: Double, loss: Double)] {
        Atmosphere.octaveBands.map { f in
            (f,
             Atmosphere.absorptionDBPerKm(freqHz: f, tempC: temp, humidityPct: humidity, pressureKPa: pressure),
             Atmosphere.lossDB(freqHz: f, tempC: temp, humidityPct: humidity, distanceM: distance, pressureKPa: pressure))
        }
    }
}
