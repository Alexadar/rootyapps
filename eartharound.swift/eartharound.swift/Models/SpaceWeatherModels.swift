//
//  SpaceWeatherModels.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import Foundation

// MARK: - Solar Wind Data
struct SolarWindData: Codable {
    let timeTag: String
    let speed: Double?
    let density: Double?
    let temperature: Double?

    enum CodingKeys: String, CodingKey {
        case timeTag = "time_tag"
        case speed
        case density
        case temperature
    }
}

// MARK: - Geomagnetic K-Index
struct KIndexData: Codable {
    let timeTag: String
    let kp: Double?
    let observedTime: String?

    enum CodingKeys: String, CodingKey {
        case timeTag = "time_tag"
        case kp = "Kp"
        case observedTime = "observed_time"
    }
}

// MARK: - Solar Flare Event
struct SolarFlareEvent: Codable {
    let beginTime: String?
    let peakTime: String?
    let endTime: String?
    let classType: String?
    let sourceLocation: String?

    enum CodingKeys: String, CodingKey {
        case beginTime = "begin_time"
        case peakTime = "peak_time"
        case endTime = "end_time"
        case classType = "class_type"
        case sourceLocation = "source_location"
    }
}

// MARK: - Space Weather Extremes Model
struct SpaceWeatherExtremes {
    var currentKIndex: Double?
    var kIndexStatus: String
    var solarWindSpeed: Double?
    var latestFlare: SolarFlareEvent?
    var flareIntensity: String
    var lastUpdate: Date

    var isExtreme: Bool {
        // K-index > 5 is considered storm conditions
        if let kp = currentKIndex, kp >= 5.0 {
            return true
        }
        // Solar wind speed > 500 km/s is elevated
        if let speed = solarWindSpeed, speed > 500 {
            return true
        }
        // X-class or M-class flares are significant
        if let flare = latestFlare?.classType, flare.hasPrefix("X") || flare.hasPrefix("M") {
            return true
        }
        return false
    }

    func getKIndexDescription() -> String {
        guard let kp = currentKIndex else { return "No Data" }

        switch kp {
        case 0..<2: return "Quiet"
        case 2..<4: return "Unsettled"
        case 4..<5: return "Active"
        case 5..<6: return "Minor Storm (G1)"
        case 6..<7: return "Moderate Storm (G2)"
        case 7..<8: return "Strong Storm (G3)"
        case 8..<9: return "Severe Storm (G4)"
        default: return "Extreme Storm (G5)"
        }
    }

    func getFlareDescription() -> String {
        guard let classType = latestFlare?.classType else { return "No Recent Flares" }

        if classType.hasPrefix("X") {
            return "X-Class (Extreme)"
        } else if classType.hasPrefix("M") {
            return "M-Class (Strong)"
        } else if classType.hasPrefix("C") {
            return "C-Class (Moderate)"
        } else {
            return "Minor Activity"
        }
    }
}
