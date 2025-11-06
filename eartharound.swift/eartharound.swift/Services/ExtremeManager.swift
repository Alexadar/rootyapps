//
//  ExtremeManager.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import Foundation

// MARK: - Extreme Thresholds
struct ExtremeThresholds {
    // Weather Thresholds
    static let temperatureExtremeCold: Double = -20
    static let temperatureVeryCold: Double = -10
    static let temperatureHot: Double = 30
    static let temperatureExtremeHeat: Double = 35

    static let windStrong: Double = 30
    static let windVeryStrong: Double = 50
    static let windStorm: Double = 75

    static let precipitationModerate: Double = 2.5
    static let precipitationHeavy: Double = 10

    static let humidityVeryLow: Int = 20
    static let humidityVeryHigh: Int = 85

    // Space Weather Thresholds
    static let kIndexActive: Double = 4.0
    static let kIndexMinorStorm: Double = 5.0
    static let kIndexModerateStorm: Double = 6.0
    static let kIndexStrongStorm: Double = 7.0

    static let solarWindElevated: Double = 450
    static let solarWindHigh: Double = 550
}

// MARK: - Extreme Event
struct ExtremeEvent: Identifiable {
    let id = UUID()
    let type: ExtremeType
    let severity: ExtremeSeverity
    let value: String
    let description: String
    let icon: String
}

enum ExtremeType {
    case temperature
    case wind
    case precipitation
    case humidity
    case kIndex
    case solarWind
    case solarFlare
}

enum ExtremeSeverity: String {
    case warning = "⚠️"
    case danger = "🔴"
    case extreme = "‼️"
}

// MARK: - Extreme Manager
class ExtremeManager {
    static let shared = ExtremeManager()

    private init() {}

    // MARK: - Analyze Weather Extremes
    func analyzeWeather(_ weather: WeatherExtremes) -> [ExtremeEvent] {
        var events: [ExtremeEvent] = []

        // Temperature
        if let temp = weather.currentTemp {
            if temp <= ExtremeThresholds.temperatureExtremeCold {
                events.append(ExtremeEvent(
                    type: .temperature,
                    severity: .extreme,
                    value: String(format: "%.1f°C", temp),
                    description: "Extreme Cold",
                    icon: "snowflake"
                ))
            } else if temp <= ExtremeThresholds.temperatureVeryCold {
                events.append(ExtremeEvent(
                    type: .temperature,
                    severity: .danger,
                    value: String(format: "%.1f°C", temp),
                    description: "Very Cold",
                    icon: "thermometer.snowflake"
                ))
            } else if temp >= ExtremeThresholds.temperatureExtremeHeat {
                events.append(ExtremeEvent(
                    type: .temperature,
                    severity: .extreme,
                    value: String(format: "%.1f°C", temp),
                    description: "Extreme Heat",
                    icon: "flame.fill"
                ))
            } else if temp >= ExtremeThresholds.temperatureHot {
                events.append(ExtremeEvent(
                    type: .temperature,
                    severity: .danger,
                    value: String(format: "%.1f°C", temp),
                    description: "Hot",
                    icon: "thermometer.sun.fill"
                ))
            }
        }

        // Wind
        if let wind = weather.windSpeed {
            if wind >= ExtremeThresholds.windStorm {
                events.append(ExtremeEvent(
                    type: .wind,
                    severity: .extreme,
                    value: String(format: "%.0f km/h", wind),
                    description: "Storm Force Winds",
                    icon: "tornado"
                ))
            } else if wind >= ExtremeThresholds.windVeryStrong {
                events.append(ExtremeEvent(
                    type: .wind,
                    severity: .danger,
                    value: String(format: "%.0f km/h", wind),
                    description: "Very Strong Winds",
                    icon: "wind"
                ))
            } else if wind >= ExtremeThresholds.windStrong {
                events.append(ExtremeEvent(
                    type: .wind,
                    severity: .warning,
                    value: String(format: "%.0f km/h", wind),
                    description: "Strong Winds",
                    icon: "wind"
                ))
            }
        }

        // Precipitation
        if let precip = weather.precipitation, precip > 0 {
            if precip >= ExtremeThresholds.precipitationHeavy {
                events.append(ExtremeEvent(
                    type: .precipitation,
                    severity: .extreme,
                    value: String(format: "%.1f mm", precip),
                    description: "Heavy Rain",
                    icon: "cloud.heavyrain.fill"
                ))
            } else if precip >= ExtremeThresholds.precipitationModerate {
                events.append(ExtremeEvent(
                    type: .precipitation,
                    severity: .warning,
                    value: String(format: "%.1f mm", precip),
                    description: "Moderate Rain",
                    icon: "cloud.rain.fill"
                ))
            }
        }

        // Humidity
        if let humidity = weather.humidity {
            if humidity <= ExtremeThresholds.humidityVeryLow {
                events.append(ExtremeEvent(
                    type: .humidity,
                    severity: .warning,
                    value: "\(humidity)%",
                    description: "Very Low Humidity",
                    icon: "humidity"
                ))
            } else if humidity >= ExtremeThresholds.humidityVeryHigh {
                events.append(ExtremeEvent(
                    type: .humidity,
                    severity: .warning,
                    value: "\(humidity)%",
                    description: "Very High Humidity",
                    icon: "humidity.fill"
                ))
            }
        }

        return events
    }

    // MARK: - Analyze Space Weather Extremes
    func analyzeSpaceWeather(_ space: SpaceWeatherExtremes) -> [ExtremeEvent] {
        var events: [ExtremeEvent] = []

        // K-Index
        if let kIndex = space.currentKIndex {
            if kIndex >= ExtremeThresholds.kIndexStrongStorm {
                events.append(ExtremeEvent(
                    type: .kIndex,
                    severity: .extreme,
                    value: String(format: "%.1f", kIndex),
                    description: "Strong Geomagnetic Storm",
                    icon: "bolt.fill"
                ))
            } else if kIndex >= ExtremeThresholds.kIndexModerateStorm {
                events.append(ExtremeEvent(
                    type: .kIndex,
                    severity: .danger,
                    value: String(format: "%.1f", kIndex),
                    description: "Moderate Geomagnetic Storm",
                    icon: "sparkles"
                ))
            } else if kIndex >= ExtremeThresholds.kIndexMinorStorm {
                events.append(ExtremeEvent(
                    type: .kIndex,
                    severity: .warning,
                    value: String(format: "%.1f", kIndex),
                    description: "Minor Geomagnetic Storm",
                    icon: "sparkle"
                ))
            }
        }

        // Solar Wind
        if let solarWind = space.solarWindSpeed {
            if solarWind >= ExtremeThresholds.solarWindHigh {
                events.append(ExtremeEvent(
                    type: .solarWind,
                    severity: .danger,
                    value: String(format: "%.0f km/s", solarWind),
                    description: "High Speed Solar Wind",
                    icon: "wind"
                ))
            } else if solarWind >= ExtremeThresholds.solarWindElevated {
                events.append(ExtremeEvent(
                    type: .solarWind,
                    severity: .warning,
                    value: String(format: "%.0f km/s", solarWind),
                    description: "Elevated Solar Wind",
                    icon: "wind"
                ))
            }
        }

        // Solar Flares
        if let flare = space.latestFlare?.classType {
            if flare.hasPrefix("X") {
                events.append(ExtremeEvent(
                    type: .solarFlare,
                    severity: .extreme,
                    value: flare,
                    description: "X-Class Solar Flare",
                    icon: "sun.max.fill"
                ))
            } else if flare.hasPrefix("M") {
                events.append(ExtremeEvent(
                    type: .solarFlare,
                    severity: .danger,
                    value: flare,
                    description: "M-Class Solar Flare",
                    icon: "sun.max"
                ))
            }
        }

        return events
    }

    // MARK: - Get All Active Extremes
    func getAllExtremes(weather: WeatherExtremes?, space: SpaceWeatherExtremes?) -> [ExtremeEvent] {
        var allEvents: [ExtremeEvent] = []

        if let weather = weather {
            allEvents.append(contentsOf: analyzeWeather(weather))
        }

        if let space = space {
            allEvents.append(contentsOf: analyzeSpaceWeather(space))
        }

        // Sort by severity
        return allEvents.sorted { event1, event2 in
            let severityOrder: [ExtremeSeverity] = [.extreme, .danger, .warning]
            let index1 = severityOrder.firstIndex(of: event1.severity) ?? 999
            let index2 = severityOrder.firstIndex(of: event2.severity) ?? 999
            return index1 < index2
        }
    }

    // MARK: - Has Active Extremes
    func hasActiveExtremes(weather: WeatherExtremes?, space: SpaceWeatherExtremes?) -> Bool {
        return !getAllExtremes(weather: weather, space: space).isEmpty
    }
}
