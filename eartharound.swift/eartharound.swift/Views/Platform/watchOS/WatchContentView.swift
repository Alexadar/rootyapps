//
//  WatchContentView.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import SwiftUI

#if os(watchOS)
struct WatchContentView: View {
    @StateObject private var viewModel = ExtremesViewModel()

    var body: some View {
        TabView {
            // Today's Extremes
            WatchExtremesCard(
                title: "Today",
                extremes: viewModel.todayExtremes
            )
            .containerBackground(.blue.gradient, for: .tabView)

            // Yesterday's Extremes
            WatchExtremesCard(
                title: "Yesterday",
                extremes: viewModel.yesterdayExtremes
            )
            .containerBackground(.purple.gradient, for: .tabView)
        }
        .tabViewStyle(.verticalPage)
        .task {
            await viewModel.fetchAllExtremes()
        }
    }
}

struct WatchExtremesCard: View {
    let title: String
    let extremes: DailyExtremes?
    @State private var selectedEvent: AggregatedEvent?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Title
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top, 8)

                if let extremes = extremes {
                    if extremes.aggregated.isEmpty {
                        Text("No extremes")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.vertical, 20)
                    } else {
                        ForEach(extremes.aggregated) { event in
                            WatchEventBadge(event: event)
                                .onTapGesture {
                                    selectedEvent = event
                                }
                        }
                    }
                } else {
                    ProgressView()
                        .tint(.white)
                        .padding(.vertical, 20)
                }
            }
            .padding(.horizontal, 4)
        }
        .sheet(item: $selectedEvent) { event in
            WatchEventDetail(event: event)
        }
    }
}

struct WatchEventBadge: View {
    let event: AggregatedEvent

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(event.icon)
                    .font(.title2)
                Text(eventName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                if event.count > 1 {
                    Text("x\(event.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                }
            }
            HStack {
                Text(valueString)
                    .font(.caption2)
                Spacer()
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor.opacity(0.8))
        )
        .foregroundColor(.white)
    }

    var eventName: String {
        switch event.type {
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

    var valueString: String {
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

    var backgroundColor: Color {
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

struct WatchEventDetail: View {
    let event: AggregatedEvent
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var eventConfig: ExtremeTypeConfig? {
        SettingsLoader.shared.settings?.extremeTypes.first { $0.id == event.type.rawValue }
    }

    var severityExplanation: String? {
        let value = event.maxValue

        switch event.type {
        case .cold:
            if value <= -30 { return "Dangerously low. Can cause frostbite in minutes." }
            else if value <= -20 { return "Very harsh cold. Extreme caution required." }
            else if value <= -10 { return "Crosses extreme cold threshold." }
            return nil

        case .heat:
            if value >= 45 { return "Dangerous heat. Potentially life-threatening." }
            else if value >= 40 { return "Intense heat. Stay hydrated." }
            else if value >= 35 { return "Crosses extreme heat threshold." }
            return nil

        case .wind:
            if value >= 90 { return "Storm-force. Significant damage possible." }
            else if value >= 70 { return "Very strong. Structural damage risk." }
            else if value >= 50 { return "Gale force. Minor damage possible." }
            return nil

        case .gust:
            if value >= 120 { return "Violent gusts. Severe damage capable." }
            else if value >= 100 { return "Dangerous gusts. Major damage risk." }
            else if value >= 70 { return "Strong gusts. Damage possible." }
            return nil

        case .rain:
            if value >= 30 { return "Torrential. Severe flooding likely." }
            else if value >= 15 { return "Very heavy. High flood risk." }
            else if value >= 5 { return "Crosses heavy rain threshold." }
            return nil

        case .geomagnetic:
            if value >= 8 { return "Severe storm (G4-G5). Power grid issues. Mid-latitude aurora." }
            else if value >= 6 { return "Strong storm (G3). Satellite impacts. Lower-latitude aurora." }
            else if value >= 5 { return "Moderate storm (G1-G2). Minor impacts. High-latitude aurora." }
            return nil

        case .solarWind:
            if value >= 800 { return "Exceptionally fast. Major storms likely." }
            else if value >= 650 { return "Very high speed. Disturbances expected." }
            else if value >= 500 { return "High-speed stream detected." }
            return nil

        case .solarFlare:
            if let str = event.stringValue {
                if str.hasPrefix("X") {
                    return "\(str) - Major flare. Radio blackouts, radiation storms possible."
                } else if str.hasPrefix("M") {
                    return "\(str) - Medium flare. Brief blackouts, aurora likely."
                }
            }
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(event.icon)
                    .font(.system(size: 50))

                Text(eventName)
                    .font(.headline)

                // Description
                if let config = eventConfig {
                    Text(config.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Peak")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(valueString)
                            .font(.body)
                            .fontWeight(.semibold)
                    }

                    if event.count > 1 {
                        HStack {
                            Text("Count")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(event.count)")
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                    }

                    if let config = eventConfig {
                        if let rangeDesc = config.rangeDescription {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Trigger")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(rangeDesc)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let typicalRange = config.typicalRange {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Expected")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(typicalRange)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                // Severity explanation
                if let explanation = severityExplanation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Context")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Text(explanation)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                    )
                }

                Button("Close") {
                    dismiss()
                }
                .font(.caption)
                .padding(.top, 8)
            }
            .padding()
        }
    }

    var eventName: String {
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

    var valueString: String {
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
}
#endif
