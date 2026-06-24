import Foundation
import Combine
import CoreLocation

enum FetchError: Equatable {
    case network
    case server
    case data
    case location

    var shortMessage: String {
        switch self {
        case .network: return "No connection"
        case .server: return "Service unavailable"
        case .data: return "Data error"
        case .location: return "Location unavailable"
        }
    }
}

@MainActor
class ExtremesViewModel: ObservableObject {
    @Published var todayExtremes: DailyExtremes?
    @Published var yesterdayExtremes: DailyExtremes?
    @Published var isLoading = false
    @Published var error: FetchError?

    private let historicalService = HistoricalWeatherService.shared
    private let locationService = LocationService.shared
    private var refreshTimer: Timer?
    private var dismissTask: Task<Void, Never>?

    func fetchAllExtremes() async {
        isLoading = true
        error = nil
        dismissTask?.cancel()

        locationService.requestLocation()
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let lat = locationService.currentLocation?.latitude ?? 40.7128
        let lon = locationService.currentLocation?.longitude ?? -74.0060

        if locationService.currentLocation == nil {
            setError(.location)
        }

        do {
            async let dailyExtremesTask = historicalService.fetchHistoricalExtremes(
                latitude: lat, longitude: lon, days: 5
            )
            async let spaceWeatherTask = SpaceWeatherService.shared.getCurrentExtremes()

            let dailyExtremes = try await dailyExtremesTask
            let spaceWeather = try await spaceWeatherTask

            var today = dailyExtremes.count >= 1 ? dailyExtremes[0] : DailyExtremes(date: Date(), events: [])

            if let kp = spaceWeather.currentKIndex, kp >= 5.0 {
                today.events.append(.geomagnetic(kp))
            }
            if let wind = spaceWeather.solarWindSpeed, wind >= 500 {
                today.events.append(.solarWind(wind))
            }
            if let flare = spaceWeather.latestFlare?.classType {
                today.events.append(.solarFlare(flare))
            }

            todayExtremes = today
            if dailyExtremes.count >= 2 {
                yesterdayExtremes = dailyExtremes[1]
            }
        } catch let urlError as URLError {
            setError(urlError.code == .notConnectedToInternet || urlError.code == .timedOut ? .network : .server)
        } catch is DecodingError {
            setError(.data)
        } catch {
            setError(.server)
        }

        isLoading = false
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchAllExtremes()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func setError(_ err: FetchError) {
        error = err
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled { error = nil }
        }
    }
}
