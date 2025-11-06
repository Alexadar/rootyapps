//
//  WeatherModels.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import Foundation

// MARK: - Open-Meteo API Response
struct OpenMeteoResponse: Codable {
    let latitude: Double
    let longitude: Double
    let timezone: String
    let current: CurrentWeather?
    let daily: DailyWeather?
}

struct CurrentWeather: Codable {
    let time: String
    let temperature2m: Double?
    let relativeHumidity2m: Int?
    let apparentTemperature: Double?
    let precipitation: Double?
    let windSpeed10m: Double?
    let windGusts10m: Double?
    let weatherCode: Int?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case relativeHumidity2m = "relative_humidity_2m"
        case apparentTemperature = "apparent_temperature"
        case precipitation
        case windSpeed10m = "wind_speed_10m"
        case windGusts10m = "wind_gusts_10m"
        case weatherCode = "weather_code"
    }
}

struct DailyWeather: Codable {
    let time: [String]?
    let temperature2mMax: [Double]?
    let temperature2mMin: [Double]?
    let precipitationSum: [Double]?
    let windSpeed10mMax: [Double]?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2mMax = "temperature_2m_max"
        case temperature2mMin = "temperature_2m_min"
        case precipitationSum = "precipitation_sum"
        case windSpeed10mMax = "wind_speed_10m_max"
    }
}

// MARK: - Weather Extremes Model
struct WeatherExtremes {
    var currentTemp: Double?
    var feelsLike: Double?
    var windSpeed: Double?
    var windGusts: Double?
    var precipitation: Double?
    var humidity: Int?
    var location: String
    var lastUpdate: Date

    var isExtreme: Bool {
        // Temperature extremes (below -10°C or above 35°C)
        if let temp = currentTemp, temp < -10 || temp > 35 {
            return true
        }
        // Wind extremes (above 50 km/h)
        if let wind = windSpeed, wind > 50 {
            return true
        }
        // Heavy precipitation (above 10mm/h)
        if let precip = precipitation, precip > 10 {
            return true
        }
        return false
    }

    func getTempStatus() -> String {
        guard let temp = currentTemp else { return "No Data" }

        switch temp {
        case ..<(-20): return "Extreme Cold"
        case (-20)..<(-10): return "Very Cold"
        case (-10)..<0: return "Cold"
        case 0..<10: return "Cool"
        case 10..<20: return "Mild"
        case 20..<30: return "Warm"
        case 30..<35: return "Hot"
        default: return "Extreme Heat"
        }
    }

    func getWindStatus() -> String {
        guard let wind = windSpeed else { return "No Data" }

        switch wind {
        case 0..<10: return "Calm"
        case 10..<20: return "Light Breeze"
        case 20..<30: return "Moderate Wind"
        case 30..<50: return "Strong Wind"
        case 50..<75: return "Very Strong"
        default: return "Storm Force"
        }
    }

    func getPrecipStatus() -> String {
        guard let precip = precipitation else { return "No Precipitation" }

        if precip == 0 {
            return "Dry"
        } else if precip < 2.5 {
            return "Light Rain"
        } else if precip < 10 {
            return "Moderate Rain"
        } else {
            return "Heavy Rain"
        }
    }
}
