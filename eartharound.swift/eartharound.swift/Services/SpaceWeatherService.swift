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

    // MARK: - Fetch Recent Solar Flares from X-ray data
    func fetchSolarFlares() async throws -> [SolarFlareEvent] {
        let urlString = "https://services.swpc.noaa.gov/json/goes/primary/xrays-7-day.json"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await session.data(from: url)

        struct XRayData: Codable {
            let timeTag: String
            let flux: Double
            let energy: String

            enum CodingKeys: String, CodingKey {
                case timeTag = "time_tag"
                case flux
                case energy
            }
        }

        let xrayData = try JSONDecoder().decode([XRayData].self, from: data)

        // Filter for 0.1-0.8nm band (standard for flare classification)
        let primaryBand = xrayData.filter { $0.energy == "0.1-0.8nm" }

        // Detect flares from flux peaks
        var flares: [SolarFlareEvent] = []
        var currentFlare: (peak: Double, time: String)? = nil

        for i in 0..<primaryBand.count {
            let flux = primaryBand[i].flux

            // X-class: >= 1e-4
            // M-class: >= 1e-5 and < 1e-4
            // C-class: >= 1e-6 and < 1e-5

            if flux >= 1e-6 {
                if currentFlare == nil || flux > currentFlare!.peak {
                    currentFlare = (flux, primaryBand[i].timeTag)
                }
            } else if let flare = currentFlare {
                // Flare ended, classify it
                let flareClass = classifyFlare(flux: flare.peak)
                let event = SolarFlareEvent(
                    beginTime: flare.time,
                    peakTime: flare.time,
                    endTime: primaryBand[i].timeTag,
                    classType: flareClass,
                    sourceLocation: nil
                )
                flares.append(event)
                currentFlare = nil
            }
        }

        // Add ongoing flare if exists
        if let flare = currentFlare {
            let flareClass = classifyFlare(flux: flare.peak)
            let event = SolarFlareEvent(
                beginTime: flare.time,
                peakTime: flare.time,
                endTime: nil,
                classType: flareClass,
                sourceLocation: nil
            )
            flares.append(event)
        }

        print("✅ Solar Flares: Detected \(flares.count) flares")
        return flares
    }

    private func classifyFlare(flux: Double) -> String {
        switch flux {
        case 1e-4...:
            let magnitude = flux / 1e-4
            return String(format: "X%.1f", magnitude)
        case 1e-5..<1e-4:
            let magnitude = flux / 1e-5
            return String(format: "M%.1f", magnitude)
        case 1e-6..<1e-5:
            let magnitude = flux / 1e-6
            return String(format: "C%.1f", magnitude)
        default:
            return "B"
        }
    }

    // MARK: - Get Current Space Weather Extremes
    func getCurrentExtremes() async throws -> SpaceWeatherExtremes {
        async let kIndexData = fetchKIndex()
        async let solarWindData = fetchSolarWind()
        async let flareData = fetchSolarFlares()

        let kData = try await kIndexData
        let windData = try await solarWindData
        let flares = try await flareData

        // Get latest K-index
        let latestKIndex = kData.last?.kp ?? 0.0

        // Get latest solar wind speed
        let latestWindSpeed = windData.last?.speed

        // Get most recent major flare (M or X class from last 24 hours)
        let now = Date()
        let oneDayAgo = now.addingTimeInterval(-86400)
        let formatter = ISO8601DateFormatter()

        let recentFlares = flares.filter { flare in
            guard let peakTime = flare.peakTime,
                  let date = formatter.date(from: peakTime) else {
                return false
            }
            return date > oneDayAgo &&
                   (flare.classType?.hasPrefix("X") == true || flare.classType?.hasPrefix("M") == true)
        }

        let latestFlare = recentFlares.last

        let extremes = SpaceWeatherExtremes(
            currentKIndex: latestKIndex,
            kIndexStatus: "",
            solarWindSpeed: latestWindSpeed,
            latestFlare: latestFlare,
            flareIntensity: latestFlare?.classType ?? "",
            lastUpdate: Date()
        )

        print("✅ Space Weather: Kp=\(latestKIndex), Wind=\(latestWindSpeed ?? 0)km/s, Flare=\(latestFlare?.classType ?? "none")")
        return extremes
    }
}
