//
//  WeatherService.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import Foundation

class WeatherService {
    static let shared = WeatherService()

    private let baseURL = "https://api.open-meteo.com/v1"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: - Fetch Current Weather + Daily Forecast
    func fetchWeather(latitude: Double, longitude: Double) async throws -> OpenMeteoResponse {
        var components = URLComponents(string: "\(baseURL)/forecast")!

        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m,wind_gusts_10m"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_sum,wind_speed_10m_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1")
        ]

        guard let url = components.url else {
            print("❌ Weather: Invalid URL")
            throw URLError(.badURL)
        }

        do {
            print("🌤️ Fetching weather from: \(url.absoluteString)")
            let (data, _) = try await session.data(from: url)

            let decoder = JSONDecoder()
            let response = try decoder.decode(OpenMeteoResponse.self, from: data)

            print("✅ Weather: Loaded for \(response.latitude), \(response.longitude)")
            return response
        } catch {
            print("❌ Weather parse error: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Get Current Weather Extremes
    func getCurrentExtremes(latitude: Double = 40.7128, longitude: Double = -74.0060, location: String = "New York") async throws -> WeatherExtremes {
        let response = try await fetchWeather(latitude: latitude, longitude: longitude)

        let extremes = WeatherExtremes(
            currentTemp: response.current?.temperature2m,
            feelsLike: response.current?.apparentTemperature,
            windSpeed: response.current?.windSpeed10m,
            windGusts: response.current?.windGusts10m,
            precipitation: response.current?.precipitation,
            humidity: response.current?.relativeHumidity2m,
            location: location,
            lastUpdate: Date()
        )

        return extremes
    }

    // MARK: - Get Weather for Multiple Locations
    func getWeatherForLocations() async throws -> [WeatherExtremes] {
        // Default cities for demo
        let locations: [(lat: Double, lon: Double, name: String)] = [
            (40.7128, -74.0060, "New York"),
            (51.5074, -0.1278, "London"),
            (35.6762, 139.6503, "Tokyo")
        ]

        var extremes: [WeatherExtremes] = []

        for location in locations {
            do {
                let weather = try await getCurrentExtremes(
                    latitude: location.lat,
                    longitude: location.lon,
                    location: location.name
                )
                extremes.append(weather)
            } catch {
                print("Failed to fetch weather for \(location.name): \(error)")
            }
        }

        return extremes
    }
}
