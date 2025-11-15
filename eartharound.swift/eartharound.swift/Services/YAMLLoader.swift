//
//  YAMLLoader.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import Foundation

struct TestDailyExtremes: Codable {
    let date: String
    let events: [TestEvent]
}

struct TestEvent: Codable {
    let type: String
    let value: Double
}

class YAMLLoader {
    static func loadTestExtremes(filename: String) -> DailyExtremes? {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "yaml", subdirectory: "test_extremes") else {
            print("❌ YAML file not found: \(filename)")
            return nil
        }

        do {
            let yamlString = try String(contentsOf: url, encoding: .utf8)
            return parseYAML(yamlString)
        } catch {
            print("❌ Failed to load YAML: \(error)")
            return nil
        }
    }

    private static func parseYAML(_ yaml: String) -> DailyExtremes? {
        var dateString: String?
        var events: [HistoricalExtremeEvent] = []

        let lines = yaml.split(separator: "\n")
        var currentEvent: (type: String?, value: Double?) = (nil, nil)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("date:") {
                dateString = trimmed
                    .replacingOccurrences(of: "date:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
            } else if trimmed.hasPrefix("- type:") {
                if let type = currentEvent.type, let value = currentEvent.value {
                    if let event = createEvent(type: type, value: value) {
                        events.append(event)
                    }
                }
                currentEvent = (
                    trimmed
                        .replacingOccurrences(of: "- type:", with: "")
                        .trimmingCharacters(in: .whitespaces),
                    nil
                )
            } else if trimmed.hasPrefix("type:") {
                currentEvent.type = trimmed
                    .replacingOccurrences(of: "type:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("value:") {
                let valueStr = trimmed
                    .replacingOccurrences(of: "value:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentEvent.value = Double(valueStr)
            }
        }

        if let type = currentEvent.type, let value = currentEvent.value {
            if let event = createEvent(type: type, value: value) {
                events.append(event)
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = dateString.flatMap { formatter.date(from: $0) } ?? Date()

        return DailyExtremes(date: date, events: events)
    }

    private static func createEvent(type: String, value: Double) -> HistoricalExtremeEvent? {
        switch type {
        case "cold": return .cold(value)
        case "heat": return .heat(value)
        case "wind": return .wind(value)
        case "gust": return .gust(value)
        case "rain": return .rain(value)
        default: return nil
        }
    }

    static func availableTests() -> [String] {
        return [
            "calm_day",
            "cold_wave",
            "heat_wave",
            "storm",
            "mixed_extremes",
            "heavy_rain"
        ]
    }
}
