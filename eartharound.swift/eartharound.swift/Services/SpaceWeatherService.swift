//
//  SpaceWeatherService.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import Foundation

class SpaceWeatherService {
    static let shared = SpaceWeatherService()

    private let baseURL = "https://services.swpc.noaa.gov"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: - Fetch K-Index (Geomagnetic Activity)
    func fetchKIndex() async throws -> [KIndexData] {
        let urlString = "\(baseURL)/products/noaa-planetary-k-index.json"
        guard let url = URL(string: urlString) else {
            print("❌ K-Index: Invalid URL")
            throw URLError(.badURL)
        }

        do {
            let (data, _) = try await session.data(from: url)

            let jsonArray = try JSONDecoder().decode([[String]].self, from: data)
            let dataRows = jsonArray.dropFirst()

            var kIndexData: [KIndexData] = []
            for row in dataRows {
                if row.count >= 2 {
                    let timeTag = row[0]
                    let kpValue = Double(row[1]) ?? 0.0
                    let kData = KIndexData(timeTag: timeTag, kp: kpValue, observedTime: timeTag)
                    kIndexData.append(kData)
                }
            }

            print("✅ K-Index: Loaded \(kIndexData.count) records")
            return kIndexData
        } catch {
            print("❌ K-Index parse error: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Fetch Solar Wind Data
    func fetchSolarWind() async throws -> [SolarWindData] {
        let urlString = "\(baseURL)/products/solar-wind/mag-1-day.json"
        guard let url = URL(string: urlString) else {
            print("❌ Solar Wind: Invalid URL")
            throw URLError(.badURL)
        }

        do {
            let (data, _) = try await session.data(from: url)

            let jsonArray = try JSONDecoder().decode([[String]].self, from: data)
            let dataRows = jsonArray.dropFirst()

            var solarWindData: [SolarWindData] = []
            for row in dataRows {
                if row.count >= 7 {
                    let timeTag = row[0]
                    let speed = Double(row[6])
                    let density = row.count > 7 ? Double(row[7]) : nil
                    let temperature = row.count > 8 ? Double(row[8]) : nil

                    let windData = SolarWindData(
                        timeTag: timeTag,
                        speed: speed,
                        density: density,
                        temperature: temperature
                    )
                    solarWindData.append(windData)
                }
            }

            print("✅ Solar Wind: Loaded \(solarWindData.count) records")
            return solarWindData
        } catch {
            print("❌ Solar Wind parse error: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Fetch Recent Solar Flares
    func fetchSolarFlares() async throws -> [SolarFlareEvent] {
        let urlString = "\(baseURL)/products/solar-wind/plasma-3-day.json"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await session.data(from: url)

        // For simplicity, we'll create mock flare structure
        // In production, you'd parse specific flare endpoints
        let jsonArray = try JSONDecoder().decode([[String]].self, from: data)

        // Return empty for now - flare data needs specific endpoint
        return []
    }

    // MARK: - Get Current Space Weather Extremes
    func getCurrentExtremes() async throws -> SpaceWeatherExtremes {
        async let kIndexData = fetchKIndex()
        async let solarWindData = fetchSolarWind()

        let kData = try await kIndexData
        let windData = try await solarWindData

        // Get latest K-index
        let latestKIndex = kData.last?.kp ?? 0.0

        // Get latest solar wind speed
        let latestWindSpeed = windData.last?.speed

        let extremes = SpaceWeatherExtremes(
            currentKIndex: latestKIndex,
            kIndexStatus: "",
            solarWindSpeed: latestWindSpeed,
            latestFlare: nil,
            flareIntensity: "",
            lastUpdate: Date()
        )

        return extremes
    }
}
