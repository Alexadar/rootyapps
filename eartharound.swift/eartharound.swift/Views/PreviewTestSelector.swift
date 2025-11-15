//
//  PreviewTestSelector.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import SwiftUI

#if DEBUG && !os(watchOS)
struct PreviewTestSelector: View {
    @State private var selectedToday = "cold_wave"
    @State private var selectedYesterday = "storm"

    let testCases = YAMLLoader.availableTests()

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview Test Data")
                    .font(.headline)

                HStack {
                    Text("Today:")
                    Picker("Today", selection: $selectedToday) {
                        ForEach(testCases, id: \.self) { test in
                            Text(test.replacingOccurrences(of: "_", with: " ").capitalized)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Text("Yesterday:")
                    Picker("Yesterday", selection: $selectedYesterday) {
                        ForEach(testCases, id: \.self) { test in
                            Text(test.replacingOccurrences(of: "_", with: " ").capitalized)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            Divider()

            ExtremesPreviewContent(
                todayTest: selectedToday,
                yesterdayTest: selectedYesterday
            )
        }
        .padding()
    }
}

struct ExtremesPreviewContent: View {
    let todayTest: String
    let yesterdayTest: String

    var todayExtremes: DailyExtremes? {
        YAMLLoader.loadTestExtremes(filename: todayTest)
    }

    var yesterdayExtremes: DailyExtremes? {
        YAMLLoader.loadTestExtremes(filename: yesterdayTest)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let today = todayExtremes {
                    ExtremesPanel(title: "Today (\(todayTest))", extremes: today)
                }

                if let yesterday = yesterdayExtremes {
                    ExtremesPanel(title: "Yesterday (\(yesterdayTest))", extremes: yesterday)
                }
            }
            .padding()
        }
    }
}

#if !os(watchOS)
#Preview("Test Selector") {
    PreviewTestSelector()
}
#endif

#Preview("Calm Day") {
    let today = DailyExtremes(date: Date(), events: [])
    let yesterday = DailyExtremes(date: Date().addingTimeInterval(-86400), events: [])

    VStack(spacing: 16) {
        ExtremesPanel(title: "Today", extremes: today)
        ExtremesPanel(title: "Yesterday", extremes: yesterday)
    }
    .padding()
}

#Preview("Cold Wave") {
    let today = DailyExtremes(date: Date(), events: [
        .cold(-15.3), .cold(-18.7), .cold(-22.1), .cold(-19.5), .cold(-16.8)
    ])
    let yesterday = DailyExtremes(date: Date().addingTimeInterval(-86400), events: [])

    VStack(spacing: 16) {
        ExtremesPanel(title: "Today", extremes: today)
        ExtremesPanel(title: "Yesterday", extremes: yesterday)
    }
    .padding()
}

#Preview("Heat Wave") {
    let today = DailyExtremes(date: Date(), events: [
        .heat(37.2), .heat(39.8), .heat(41.3), .heat(40.1)
    ])
    let yesterday = DailyExtremes(date: Date().addingTimeInterval(-86400), events: [])

    VStack(spacing: 16) {
        ExtremesPanel(title: "Today", extremes: today)
        ExtremesPanel(title: "Yesterday", extremes: yesterday)
    }
    .padding()
}

#Preview("Storm") {
    let today = DailyExtremes(date: Date(), events: [
        .wind(65.2), .wind(72.8), .wind(68.3),
        .gust(85.5), .gust(92.1), .gust(88.7), .gust(95.3),
        .rain(12.5), .rain(8.7)
    ])
    let yesterday = DailyExtremes(date: Date().addingTimeInterval(-86400), events: [])

    VStack(spacing: 16) {
        ExtremesPanel(title: "Today", extremes: today)
        ExtremesPanel(title: "Yesterday", extremes: yesterday)
    }
    .padding()
}

#Preview("Mixed Extremes") {
    let today = DailyExtremes(date: Date(), events: [
        .cold(-12.5), .cold(-14.8), .wind(55.3), .gust(75.2), .rain(6.8)
    ])
    let yesterday = DailyExtremes(date: Date().addingTimeInterval(-86400), events: [
        .heat(37.2), .heat(39.8)
    ])

    VStack(spacing: 16) {
        ExtremesPanel(title: "Today", extremes: today)
        ExtremesPanel(title: "Yesterday", extremes: yesterday)
    }
    .padding()
}

#Preview("Heavy Rain") {
    let today = DailyExtremes(date: Date(), events: [
        .rain(15.3), .rain(18.7), .rain(22.1), .rain(19.5), .rain(16.8), .rain(14.2), .rain(11.9)
    ])
    let yesterday = DailyExtremes(date: Date().addingTimeInterval(-86400), events: [
        .wind(65.2), .gust(85.5)
    ])

    VStack(spacing: 16) {
        ExtremesPanel(title: "Today", extremes: today)
        ExtremesPanel(title: "Yesterday", extremes: yesterday)
    }
    .padding()
}

#Preview("Full Chaos") {
    let today = DailyExtremes(date: Date(), events: [
        .wind(65.2), .wind(72.8), .gust(85.5), .gust(92.1), .rain(12.5), .rain(8.7)
    ])
    let yesterday = DailyExtremes(date: Date().addingTimeInterval(-86400), events: [
        .cold(-12.5), .cold(-14.8), .wind(55.3), .gust(75.2), .rain(6.8)
    ])

    VStack(spacing: 16) {
        ExtremesPanel(title: "Today", extremes: today)
        ExtremesPanel(title: "Yesterday", extremes: yesterday)
    }
    .padding()
}

#Preview("Space Weather - Geomagnetic Storm") {
    let space = SpaceWeatherExtremes(
        currentKIndex: 7.5,
        kIndexStatus: "Strong Storm (G3)",
        solarWindSpeed: 450,
        latestFlare: nil,
        flareIntensity: "None",
        lastUpdate: Date()
    )

    SpaceWeatherPanel(title: "Space Weather", extremes: space)
        .padding()
}

#Preview("Space Weather - Solar Wind + Flare") {
    let flare = SolarFlareEvent(
        beginTime: "2025-01-10T12:00:00Z",
        peakTime: "2025-01-10T12:15:00Z",
        endTime: "2025-01-10T12:30:00Z",
        classType: "X2.1",
        sourceLocation: "N15W30"
    )
    let space = SpaceWeatherExtremes(
        currentKIndex: 3.5,
        kIndexStatus: "Unsettled",
        solarWindSpeed: 650,
        latestFlare: flare,
        flareIntensity: "X-Class (Extreme)",
        lastUpdate: Date()
    )

    SpaceWeatherPanel(title: "Space Weather", extremes: space)
        .padding()
}

#Preview("Full System - Weather + Space") {
    let today = DailyExtremes(date: Date(), events: [
        .wind(65.2), .wind(72.8), .gust(85.5), .rain(12.5),
        .geomagnetic(6.5), .solarWind(580)
    ])
    let yesterday = DailyExtremes(date: Date().addingTimeInterval(-86400), events: [
        .cold(-12.5), .heat(37.2), .solarFlare("X2.1")
    ])

    VStack(spacing: 16) {
        ExtremesPanel(title: "Today", extremes: today)
        ExtremesPanel(title: "Yesterday", extremes: yesterday)
    }
    .padding()
}
#endif
