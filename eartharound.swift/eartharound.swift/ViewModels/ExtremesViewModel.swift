//
//  ExtremesViewModel.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import Foundation
import Combine
import CoreLocation

@MainActor
class ExtremesViewModel: ObservableObject {
    @Published var todayExtremes: DailyExtremes?
    @Published var yesterdayExtremes: DailyExtremes?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let historicalService = HistoricalWeatherService.shared
    private let locationService = LocationService.shared
    private var refreshTimer: Timer?

    // MARK: - Fetch All Data
    func fetchAllExtremes() async {
        print("🔄 Refreshing data at \(Date().formatted(date: .omitted, time: .standard))")
        isLoading = true
        errorMessage = nil

        locationService.requestLocation()
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        do {
            let lat = locationService.currentLocation?.latitude ?? 40.7128
            let lon = locationService.currentLocation?.longitude ?? -74.0060

            // Fetch weather and space data concurrently
            async let dailyExtremesTask = historicalService.fetchHistoricalExtremes(
                latitude: lat,
                longitude: lon,
                days: 5
            )
            async let spaceWeatherTask = SpaceWeatherService.shared.getCurrentExtremes()

            let dailyExtremes = try await dailyExtremesTask
            let spaceWeather = try await spaceWeatherTask

            // Add space weather events to today
            var today = dailyExtremes.count >= 1 ? dailyExtremes[0] : DailyExtremes(date: Date(), events: [])

            // Add geomagnetic storm if Kp >= 5
            if let kp = spaceWeather.currentKIndex, kp >= 5.0 {
                today.events.append(.geomagnetic(kp))
            }

            // Add solar wind if >= 500 km/s
            if let wind = spaceWeather.solarWindSpeed, wind >= 500 {
                today.events.append(.solarWind(wind))
            }

            // Add major flare if exists
            if let flare = spaceWeather.latestFlare?.classType {
                today.events.append(.solarFlare(flare))
            }

            todayExtremes = today

            if dailyExtremes.count >= 2 {
                yesterdayExtremes = dailyExtremes[1]
            }

        } catch {
            errorMessage = "Failed to fetch data: \(error.localizedDescription)"
            print("Error fetching extremes: \(error)")
        }

        isLoading = false
    }

    // MARK: - Start Auto Refresh
    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchAllExtremes()
            }
        }
    }

    // MARK: - Stop Auto Refresh
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
