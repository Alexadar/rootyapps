//
//  SettingsLoader.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import Foundation

struct ExtremesSettings {
    let dataTypes: DataTypes
    let extremeTypes: [ExtremeTypeConfig]
}

struct DataTypes {
    let temperature: ThresholdConfig
    let wind: ThresholdConfig
    let gust: ThresholdConfig
    let precipitation: ThresholdConfig
}

struct ThresholdConfig {
    let unit: String
    let coldThreshold: Double?
    let heatThreshold: Double?
    let extremeThreshold: Double?
}

struct ExtremeTypeConfig {
    let id: String
    let icon: String
    let color: String
    let description: String
    let threshold: Double?
    let unit: String?
    let rangeDescription: String?
    let typicalRange: String?
}

class SettingsLoader {
    static let shared = SettingsLoader()
    private(set) var settings: ExtremesSettings?

    private init() {
        loadSettings()
    }

    private func loadSettings() {
        guard let url = Bundle.main.url(forResource: "settings", withExtension: "yaml", subdirectory: "Resources") else {
            print("❌ Settings file not found")
            return
        }

        do {
            let yamlString = try String(contentsOf: url, encoding: .utf8)
            settings = parseSettings(yamlString)
            print("✅ Settings loaded")
        } catch {
            print("❌ Failed to load settings: \(error)")
        }
    }

    private func parseSettings(_ yaml: String) -> ExtremesSettings {
        var tempUnit = "celsius"
        var coldThreshold: Double = -10.0
        var heatThreshold: Double = 35.0
        var windUnit = "km/h"
        var windThreshold: Double = 50.0
        var gustUnit = "km/h"
        var gustThreshold: Double = 70.0
        var precipUnit = "mm"
        var precipThreshold: Double = 5.0
        var extremeTypes: [ExtremeTypeConfig] = []

        let lines = yaml.split(separator: "\n")
        var currentSection: String?
        var currentType: (id: String?, icon: String?, color: String?, desc: String?, threshold: Double?, unit: String?, rangeDesc: String?, typicalRange: String?) = (nil, nil, nil, nil, nil, nil, nil, nil)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("data_types:") {
                currentSection = "data_types"
            } else if trimmed.hasPrefix("extreme_types:") {
                currentSection = "extreme_types"
            } else if trimmed.hasPrefix("temperature:") {
                currentSection = "temperature"
            } else if trimmed.hasPrefix("wind:") {
                currentSection = "wind"
            } else if trimmed.hasPrefix("gust:") {
                currentSection = "gust"
            } else if trimmed.hasPrefix("precipitation:") {
                currentSection = "precipitation"
            } else if trimmed.hasPrefix("- id:") {
                if let id = currentType.id, let icon = currentType.icon, let color = currentType.color, let desc = currentType.desc {
                    extremeTypes.append(ExtremeTypeConfig(
                        id: id,
                        icon: icon,
                        color: color,
                        description: desc,
                        threshold: currentType.threshold,
                        unit: currentType.unit,
                        rangeDescription: currentType.rangeDesc,
                        typicalRange: currentType.typicalRange
                    ))
                }
                currentType = (
                    extractValue(from: trimmed, key: "- id:"),
                    nil, nil, nil, nil, nil, nil, nil
                )
            } else if let section = currentSection {
                if trimmed.hasPrefix("unit:") {
                    let value = extractValue(from: trimmed, key: "unit:")
                    switch section {
                    case "temperature": tempUnit = value ?? "celsius"
                    case "wind": windUnit = value ?? "km/h"
                    case "gust": gustUnit = value ?? "km/h"
                    case "precipitation": precipUnit = value ?? "mm"
                    default: break
                    }
                } else if trimmed.hasPrefix("cold_threshold:") {
                    coldThreshold = extractDouble(from: trimmed, key: "cold_threshold:") ?? -10.0
                } else if trimmed.hasPrefix("heat_threshold:") {
                    heatThreshold = extractDouble(from: trimmed, key: "heat_threshold:") ?? 35.0
                } else if trimmed.hasPrefix("extreme_threshold:") {
                    let val = extractDouble(from: trimmed, key: "extreme_threshold:") ?? 0.0
                    switch section {
                    case "wind": windThreshold = val
                    case "gust": gustThreshold = val
                    case "precipitation": precipThreshold = val
                    default: break
                    }
                } else if trimmed.hasPrefix("icon:") {
                    currentType.icon = extractValue(from: trimmed, key: "icon:")
                } else if trimmed.hasPrefix("color:") {
                    currentType.color = extractValue(from: trimmed, key: "color:")
                } else if trimmed.hasPrefix("description:") && !trimmed.hasPrefix("range_description:") {
                    currentType.desc = extractValue(from: trimmed, key: "description:")
                } else if trimmed.hasPrefix("threshold:") {
                    currentType.threshold = extractDouble(from: trimmed, key: "threshold:")
                } else if trimmed.hasPrefix("unit:") && section == "extreme_types" {
                    currentType.unit = extractValue(from: trimmed, key: "unit:")
                } else if trimmed.hasPrefix("range_description:") {
                    currentType.rangeDesc = extractValue(from: trimmed, key: "range_description:")
                } else if trimmed.hasPrefix("typical_range:") {
                    currentType.typicalRange = extractValue(from: trimmed, key: "typical_range:")
                }
            }
        }

        if let id = currentType.id, let icon = currentType.icon, let color = currentType.color, let desc = currentType.desc {
            extremeTypes.append(ExtremeTypeConfig(
                id: id,
                icon: icon,
                color: color,
                description: desc,
                threshold: currentType.threshold,
                unit: currentType.unit,
                rangeDescription: currentType.rangeDesc,
                typicalRange: currentType.typicalRange
            ))
        }

        let dataTypes = DataTypes(
            temperature: ThresholdConfig(unit: tempUnit, coldThreshold: coldThreshold, heatThreshold: heatThreshold, extremeThreshold: nil),
            wind: ThresholdConfig(unit: windUnit, coldThreshold: nil, heatThreshold: nil, extremeThreshold: windThreshold),
            gust: ThresholdConfig(unit: gustUnit, coldThreshold: nil, heatThreshold: nil, extremeThreshold: gustThreshold),
            precipitation: ThresholdConfig(unit: precipUnit, coldThreshold: nil, heatThreshold: nil, extremeThreshold: precipThreshold)
        )

        return ExtremesSettings(dataTypes: dataTypes, extremeTypes: extremeTypes)
    }

    private func extractValue(from line: String, key: String) -> String? {
        return line
            .replacingOccurrences(of: key, with: "")
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\"", with: "")
    }

    private func extractDouble(from line: String, key: String) -> Double? {
        guard let str = extractValue(from: line, key: key) else { return nil }
        return Double(str)
    }

    // Convenience accessors
    var coldThreshold: Double {
        settings?.dataTypes.temperature.coldThreshold ?? -10.0
    }

    var heatThreshold: Double {
        settings?.dataTypes.temperature.heatThreshold ?? 35.0
    }

    var windThreshold: Double {
        settings?.dataTypes.wind.extremeThreshold ?? 50.0
    }

    var gustThreshold: Double {
        settings?.dataTypes.gust.extremeThreshold ?? 70.0
    }

    var precipThreshold: Double {
        settings?.dataTypes.precipitation.extremeThreshold ?? 5.0
    }
}
