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
    @Published var weatherExtremes: WeatherExtremes?
    @Published var spaceExtremes: SpaceWeatherExtremes?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let weatherService = WeatherService.shared
    private let spaceWeatherService = SpaceWeatherService.shared
    private let locationService = LocationService.shared
    private var refreshTimer: Timer?

    // MARK: - Fetch All Data
    func fetchAllExtremes() async {
        print("🔄 Refreshing data at \(Date().formatted(date: .omitted, time: .standard))")
        isLoading = true
        errorMessage = nil

        // Request location
        locationService.requestLocation()

        // Wait briefly for location
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        do {
            // Use current location or default to New York
            let lat = locationService.currentLocation?.latitude ?? 40.7128
            let lon = locationService.currentLocation?.longitude ?? -74.0060
            let location = locationService.locationName

            // Fetch both weather and space data concurrently
            async let weather = weatherService.getCurrentExtremes(latitude: lat, longitude: lon, location: location)
            async let space = spaceWeatherService.getCurrentExtremes()

            weatherExtremes = try await weather
            spaceExtremes = try await space

        } catch {
            errorMessage = "Failed to fetch data: \(error.localizedDescription)"
            print("Error fetching extremes: \(error)")
        }

        isLoading = false
    }

    // MARK: - Fetch Weather Only
    func fetchWeatherExtremes(latitude: Double = 40.7128, longitude: Double = -74.0060, location: String = "New York") async {
        do {
            weatherExtremes = try await weatherService.getCurrentExtremes(
                latitude: latitude,
                longitude: longitude,
                location: location
            )
        } catch {
            errorMessage = "Weather fetch failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Fetch Space Weather Only
    func fetchSpaceExtremes() async {
        do {
            spaceExtremes = try await spaceWeatherService.getCurrentExtremes()
        } catch {
            errorMessage = "Space weather fetch failed: \(error.localizedDescription)"
        }
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
