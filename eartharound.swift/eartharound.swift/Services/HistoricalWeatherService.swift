//
//  HistoricalWeatherService.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import Foundation
import CoreLocation

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
        let valueStr = String(format: "%.1f", maxValue)
        switch type {
        case .cold: return "\(icon)\(countStr) \(valueStr)°C"
        case .heat: return "\(icon)\(countStr) \(valueStr)°C"
        case .wind: return "\(icon)\(countStr) \(valueStr)km/h"
        case .gust: return "\(icon)\(countStr) \(valueStr)km/h"
        case .rain: return "\(icon)\(countStr) \(valueStr)mm"
        case .geomagnetic: return "\(icon)\(countStr) Kp \(valueStr)"
        case .solarWind: return "\(icon)\(countStr) \(valueStr)km/s"
        case .solarFlare: return "\(icon)\(countStr) \(stringValue ?? "")"
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
