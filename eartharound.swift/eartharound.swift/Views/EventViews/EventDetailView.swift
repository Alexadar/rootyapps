//
//  EventDetailView.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import SwiftUI

struct EventDetailView: View {
    let event: AggregatedEvent
    let onDismiss: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var eventConfig: ExtremeTypeConfig? {
        SettingsLoader.shared.settings?.extremeTypes.first { $0.id == event.type.rawValue }
    }

    var severityExplanation: String? {
        let value = event.maxValue

        switch event.type {
        case .cold:
            if value <= -30 { return "Extreme cold. At \(String(format: "%.1f", value))°C, this is dangerously low and can cause frostbite in minutes. Well below typical winter minimums." }
            else if value <= -20 { return "Severe cold. At \(String(format: "%.1f", value))°C, this is very harsh cold requiring extreme caution outdoors." }
            else if value <= -10 { return "Significant cold. At \(String(format: "%.1f", value))°C, this just crosses the extreme threshold." }
            return nil

        case .heat:
            if value >= 45 { return "Extreme heat. At \(String(format: "%.1f", value))°C, this is dangerous and potentially life-threatening. Among the highest temperatures recorded." }
            else if value >= 40 { return "Severe heat. At \(String(format: "%.1f", value))°C, this is intense heat requiring caution and hydration." }
            else if value >= 35 { return "Significant heat. At \(String(format: "%.1f", value))°C, this crosses the extreme heat threshold." }
            return nil

        case .wind:
            if value >= 90 { return "Extreme wind. At \(String(format: "%.0f", value)) km/h, this is storm-force wind causing significant damage. Near hurricane strength." }
            else if value >= 70 { return "Strong gale. At \(String(format: "%.0f", value)) km/h, this is very strong wind causing structural damage." }
            else if value >= 50 { return "Gale force. At \(String(format: "%.0f", value)) km/h, this crosses the extreme wind threshold with potential for minor damage." }
            return nil

        case .gust:
            if value >= 120 { return "Extreme gusts. At \(String(format: "%.0f", value)) km/h, these are violent gusts capable of severe damage. Hurricane-force." }
            else if value >= 100 { return "Severe gusts. At \(String(format: "%.0f", value)) km/h, these are dangerous gusts causing significant damage." }
            else if value >= 70 { return "Strong gusts. At \(String(format: "%.0f", value)) km/h, these cross the extreme threshold with potential for damage." }
            return nil

        case .rain:
            if value >= 30 { return "Extreme rainfall. At \(String(format: "%.1f", value)) mm/h, this is torrential rain causing flooding. Among the highest rates possible." }
            else if value >= 15 { return "Heavy rainfall. At \(String(format: "%.1f", value)) mm/h, this is very heavy rain with high flooding risk." }
            else if value >= 5 { return "Significant rainfall. At \(String(format: "%.1f", value)) mm/h, this crosses the extreme threshold." }
            return nil

        case .geomagnetic:
            if value >= 8 { return "Extreme storm (G4-G5). Kp \(String(format: "%.1f", value)) indicates a severe geomagnetic storm. Can cause widespread power grid problems and damage satellites. Aurora visible at mid-latitudes." }
            else if value >= 6 { return "Strong storm (G3). Kp \(String(format: "%.1f", value)) indicates a significant geomagnetic disturbance. May affect power systems and satellites. Aurora visible at lower latitudes." }
            else if value >= 5 { return "Moderate storm (G1-G2). Kp \(String(format: "%.1f", value)) crosses the storm threshold. Minor impacts on satellites and power grids. Aurora visible at high latitudes." }
            return nil

        case .solarWind:
            if value >= 800 { return "Extreme solar wind. At \(String(format: "%.0f", value)) km/s, this is an exceptionally fast stream that can trigger major geomagnetic storms. Nearly double normal speed." }
            else if value >= 650 { return "Very high speed. At \(String(format: "%.0f", value)) km/s, this is significantly elevated solar wind that can cause geomagnetic disturbances." }
            else if value >= 500 { return "High-speed stream. At \(String(format: "%.0f", value)) km/s, this crosses the threshold for enhanced solar wind." }
            return nil

        case .solarFlare:
            if let str = event.stringValue {
                if str.hasPrefix("X") {
                    return "X-class flare. \(str) is a major flare capable of causing radio blackouts, radiation storms, and powerful geomagnetic storms. These are the most intense solar eruptions."
                } else if str.hasPrefix("M") {
                    return "M-class flare. \(str) is a medium-strength flare that can cause brief radio blackouts and minor radiation storms. Can trigger aurora displays."
                }
            }
            return nil
        }
    }

    var body: some View {
        ZStack {
            // Background overlay - adapts to color scheme
            Color.black.opacity(colorScheme == .dark ? 0.4 : 0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            // Detail Card
            VStack(spacing: 24) {
                // Header
                HStack {
                    Text("Event Details")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }

                // Icon
                Text(event.icon)
                    .font(.system(size: 80))

                // Event Type
                VStack(spacing: 8) {
                    Text("Type")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(eventTypeName)
                        .font(.title)
                        .fontWeight(.semibold)

                    // Description
                    if let config = eventConfig {
                        Text(config.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }

                Divider()

                // Details Grid
                VStack(spacing: 16) {
                    DetailRow(
                        label: "Peak Value",
                        value: formattedValue
                    )

                    if event.count > 1 {
                        DetailRow(
                            label: "Occurrences",
                            value: "\(event.count)"
                        )
                    }

                    // Range information from settings
                    if let config = eventConfig {
                        if let rangeDesc = config.rangeDescription {
                            DetailRow(
                                label: "Trigger",
                                value: rangeDesc
                            )
                        }

                        if let typicalRange = config.typicalRange {
                            DetailRow(
                                label: "Expected Range",
                                value: typicalRange
                            )
                        }
                    }
                }

                // Severity explanation
                if let explanation = severityExplanation {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Severity Context")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        Text(explanation)
                            .font(.body)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                    )
                    .padding(.horizontal, 32)
                }

                // Color Badge
                RoundedRectangle(cornerRadius: 8)
                    .fill(eventColor)
                    .frame(height: 4)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
                    .shadow(color: colorScheme == .dark ? Color.black.opacity(0.5) : Color.black.opacity(0.2), radius: 20)
            )
            .padding(40)
        }
    }

    var eventTypeName: String {
        switch event.type {
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

    var formattedValue: String {
        if let str = event.stringValue, event.type == .solarFlare {
            return str
        }
        let valueStr = String(format: "%.1f", event.maxValue)
        switch event.type {
        case .cold, .heat: return "\(valueStr)°C"
        case .wind, .gust: return "\(valueStr)km/h"
        case .rain: return "\(valueStr)mm"
        case .geomagnetic: return "Kp \(valueStr)"
        case .solarWind: return "\(valueStr)km/s"
        case .solarFlare: return valueStr
        }
    }

    var eventColor: Color {
        switch event.type {
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
}

struct DetailRow: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
        )
    }
}
