//
//  HistoricalWeatherService.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import Foundation
import CoreLocation
import SwiftUI

class HistoricalWeatherService {
    static let shared = HistoricalWeatherService()

    private let baseURL = "https://api.open-meteo.com/v1"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    func fetchHistoricalExtremes(latitude: Double, longitude: Double, days: Int = 5) async throws -> [DailyExtremes] {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDate)!

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var components = URLComponents(string: "\(baseURL)/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "start_date", value: dateFormatter.string(from: startDate)),
            URLQueryItem(name: "end_date", value: dateFormatter.string(from: endDate)),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation,wind_speed_10m,wind_gusts_10m,relative_humidity_2m"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(HistoricalWeatherResponse.self, from: data)

        return quantizeToDailyExtremes(response: response)
    }

    private func quantizeToDailyExtremes(response: HistoricalWeatherResponse) -> [DailyExtremes] {
        guard let times = response.hourly?.time,
              let temps = response.hourly?.temperature2m,
              let precips = response.hourly?.precipitation,
              let winds = response.hourly?.windSpeed10m,
              let gusts = response.hourly?.windGusts10m else {
            return []
        }

        var dailyMap: [String: DailyExtremes] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"

        for i in 0..<times.count {
            guard let date = dateFormatter.date(from: times[i]) else { continue }
            let dayKey = Calendar.current.startOfDay(for: date)
            let dayString = DateFormatter.localizedString(from: dayKey, dateStyle: .short, timeStyle: .none)

            if dailyMap[dayString] == nil {
                dailyMap[dayString] = DailyExtremes(date: dayKey, events: [])
            }

            // Detect extremes using settings thresholds
            var events: [HistoricalExtremeEvent] = []
            let settings = SettingsLoader.shared

            // Temperature extremes
            if let temp = temps[safe: i], let tempValue = temp {
                if tempValue < settings.coldThreshold { events.append(.cold(tempValue)) }
                if tempValue > settings.heatThreshold { events.append(.heat(tempValue)) }
            }

            // Wind extremes
            if let wind = winds[safe: i], let windValue = wind, windValue > settings.windThreshold {
                events.append(.wind(windValue))
            }
            if let gust = gusts[safe: i], let gustValue = gust, gustValue > settings.gustThreshold {
                events.append(.gust(gustValue))
            }

            // Precipitation extremes
            if let precip = precips[safe: i], let precipValue = precip, precipValue > settings.precipThreshold {
                events.append(.rain(precipValue))
            }

            dailyMap[dayString]?.events.append(contentsOf: events)
        }

        return dailyMap.values.sorted { $0.date > $1.date }
    }
}

// MARK: - Models
struct HistoricalWeatherResponse: Codable {
    let latitude: Double
    let longitude: Double
    let hourly: HourlyWeather?
}

struct HourlyWeather: Codable {
    let time: [String]?
    let temperature2m: [Double?]?
    let precipitation: [Double?]?
    let windSpeed10m: [Double?]?
    let windGusts10m: [Double?]?
    let relativeHumidity2m: [Int?]?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case precipitation
        case windSpeed10m = "wind_speed_10m"
        case windGusts10m = "wind_gusts_10m"
        case relativeHumidity2m = "relative_humidity_2m"
    }
}

struct DailyExtremes {
    let date: Date
    var events: [HistoricalExtremeEvent]

    var aggregated: [AggregatedEvent] {
        var counts: [ExtremeEventType: (count: Int, values: [Double], stringValues: [String])] = [:]

        for event in events {
            let type = event.type
            if counts[type] == nil {
                counts[type] = (0, [], [])
            }
            counts[type]?.count += 1
            counts[type]?.values.append(event.value)
            if let str = event.stringValue {
                counts[type]?.stringValues.append(str)
            }
        }

        return counts.map { type, data in
            let maxValue = data.values.max() ?? 0
            let stringValue = data.stringValues.first
            return AggregatedEvent(type: type, count: data.count, maxValue: maxValue, stringValue: stringValue)
        }.sorted { $0.type.rawValue < $1.type.rawValue }
    }
}

enum HistoricalExtremeEvent {
    case cold(Double)
    case heat(Double)
    case wind(Double)
    case gust(Double)
    case rain(Double)
    case geomagnetic(Double)
    case solarWind(Double)
    case solarFlare(String)

    var type: ExtremeEventType {
        switch self {
        case .cold: return .cold
        case .heat: return .heat
        case .wind: return .wind
        case .gust: return .gust
        case .rain: return .rain
        case .geomagnetic: return .geomagnetic
        case .solarWind: return .solarWind
        case .solarFlare: return .solarFlare
        }
    }

    var value: Double {
        switch self {
        case .cold(let v), .heat(let v), .wind(let v), .gust(let v), .rain(let v), .geomagnetic(let v), .solarWind(let v):
            return v
        case .solarFlare: return 0
        }
    }

    var stringValue: String? {
        switch self {
        case .solarFlare(let s): return s
        default: return nil
        }
    }
}

enum ExtremeEventType: String {
    case cold, heat, wind, gust, rain, geomagnetic, solarWind, solarFlare
}

struct AggregatedEvent: Identifiable, Equatable {
    let id = UUID()
    let type: ExtremeEventType
    let count: Int
    let maxValue: Double
    let stringValue: String?

    static func == (lhs: AggregatedEvent, rhs: AggregatedEvent) -> Bool {
        lhs.id == rhs.id
    }

    var icon: String {
        let settings = SettingsLoader.shared.settings
        let config = settings?.extremeTypes.first { $0.id == type.rawValue }
        return config?.icon ?? {
            switch type {
            case .cold: return "❄️"
            case .heat: return "🔥"
            case .wind: return "💨"
            case .gust: return "🌪️"
            case .rain: return "🌧️"
            case .geomagnetic: return "🌍"
            case .solarWind: return "🌬️"
            case .solarFlare: return "☀️"
            }
        }()
    }

    var label: String {
        let countStr = count > 1 ? "x\(count)" : ""
        return "\(icon)\(countStr) \(formattedValue)"
    }

    var displayName: String {
        switch type {
        case .cold: return "Cold"
        case .heat: return "Heat"
        case .wind: return "Wind"
        case .gust: return "Gust"
        case .rain: return "Rain"
        case .geomagnetic: return "Geomagnetic"
        case .solarWind: return "Solar Wind"
        case .solarFlare: return "Solar Flare"
        }
    }

    var shortDisplayName: String {
        switch type {
        case .cold: return "Cold"
        case .heat: return "Heat"
        case .wind: return "Wind"
        case .gust: return "Gust"
        case .rain: return "Rain"
        case .geomagnetic: return "Geo"
        case .solarWind: return "Solar"
        case .solarFlare: return "Flare"
        }
    }

    var formattedValue: String {
        if let str = stringValue, type == .solarFlare { return str }
        let v = String(format: "%.1f", maxValue)
        switch type {
        case .cold, .heat: return "\(v)°C"
        case .wind, .gust: return "\(v)km/h"
        case .rain: return "\(v)mm"
        case .geomagnetic: return "Kp \(v)"
        case .solarWind: return "\(v)km/s"
        case .solarFlare: return v
        }
    }

    var themeColor: Color {
        let settings = SettingsLoader.shared.settings
        if let config = settings?.extremeTypes.first(where: { $0.id == type.rawValue }) {
            switch config.color.lowercased() {
            case "blue": return .blue
            case "red": return .red
            case "gray", "grey": return .gray
            case "purple": return .purple
            case "cyan": return .cyan
            case "green": return .green
            case "orange": return .orange
            case "yellow": return .yellow
            default: break
            }
        }
        switch type {
        case .cold: return Color(red: 0.0, green: 0.48, blue: 0.80)
        case .heat: return Color(red: 1.0, green: 0.23, blue: 0.19)
        case .wind: return Color(red: 0.56, green: 0.56, blue: 0.58)
        case .gust: return Color(red: 0.69, green: 0.32, blue: 0.87)
        case .rain: return Color(red: 0.20, green: 0.68, blue: 0.90)
        case .geomagnetic: return Color(red: 0.20, green: 0.78, blue: 0.35)
        case .solarWind: return Color(red: 1.0, green: 0.58, blue: 0.0)
        case .solarFlare: return Color(red: 0.85, green: 0.65, blue: 0.15)
        }
    }

    var severityExplanation: String? {
        let value = maxValue
        switch type {
        case .cold:
            if value <= -30 { return "Dangerously low. Can cause frostbite in minutes." }
            else if value <= -20 { return "Very harsh cold. Extreme caution required." }
            else if value <= -10 { return "Crosses extreme cold threshold." }
        case .heat:
            if value >= 45 { return "Dangerous heat. Potentially life-threatening." }
            else if value >= 40 { return "Intense heat. Stay hydrated." }
            else if value >= 35 { return "Crosses extreme heat threshold." }
        case .wind:
            if value >= 90 { return "Storm-force. Significant damage possible." }
            else if value >= 70 { return "Very strong. Structural damage risk." }
            else if value >= 50 { return "Gale force. Minor damage possible." }
        case .gust:
            if value >= 120 { return "Violent gusts. Severe damage capable." }
            else if value >= 100 { return "Dangerous gusts. Major damage risk." }
            else if value >= 70 { return "Strong gusts. Damage possible." }
        case .rain:
            if value >= 30 { return "Torrential. Severe flooding likely." }
            else if value >= 15 { return "Very heavy. High flood risk." }
            else if value >= 5 { return "Crosses heavy rain threshold." }
        case .geomagnetic:
            if value >= 8 { return "Severe storm (G4-G5). Power grid issues. Mid-latitude aurora." }
            else if value >= 6 { return "Strong storm (G3). Lower-latitude aurora." }
            else if value >= 5 { return "Moderate storm (G1-G2). High-latitude aurora." }
        case .solarWind:
            if value >= 800 { return "Exceptionally fast. Major storms likely." }
            else if value >= 650 { return "Very high speed. Disturbances expected." }
            else if value >= 500 { return "High-speed stream detected." }
        case .solarFlare:
            if let str = stringValue {
                if str.hasPrefix("X") { return "\(str) - Major flare. Radio blackouts possible." }
                else if str.hasPrefix("M") { return "\(str) - Medium flare. Aurora likely." }
            }
        }
        return nil
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
