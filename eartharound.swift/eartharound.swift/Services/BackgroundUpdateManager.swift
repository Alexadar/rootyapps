//
//  BackgroundUpdateManager.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import Foundation
import CoreLocation

#if os(iOS) || os(tvOS)
import BackgroundTasks

class BackgroundUpdateManager {
    static let shared = BackgroundUpdateManager()

    private let taskIdentifier = "oleksandr.aisixteen.eartharound-swift.refresh"

    private init() {}

    // MARK: - Register Background Tasks
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        print("✅ Background task registered: \(taskIdentifier)")
    }

    // MARK: - Schedule Next Background Update
    func scheduleBackgroundUpdate() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)

        // Request update in 1 hour (system may delay)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600) // 1 hour

        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Background update scheduled for 1 hour from now")
        } catch {
            print("❌ Could not schedule background update: \(error)")
        }
    }

    // MARK: - Handle Background Update
    private func handleAppRefresh(task: BGAppRefreshTask) {
        print("🔄 Background update started at \(Date())")

        // Schedule next update
        scheduleBackgroundUpdate()

        // Create background task
        let updateTask = Task {
            do {
                // Fetch fresh extremes data
                let historicalService = HistoricalWeatherService.shared

                // Use default location for background update
                let lat = 40.7128
                let lon = -74.0060

                let extremes = try await historicalService.fetchHistoricalExtremes(
                    latitude: lat,
                    longitude: lon,
                    days: 5
                )

                print("✅ Background update completed: \(extremes.count) days fetched")
                task.setTaskCompleted(success: true)
            } catch {
                print("❌ Background update failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }

        // Handle task expiration
        task.expirationHandler = {
            print("⚠️ Background update expired")
            updateTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Cancel All Background Tasks
    func cancelAllBackgroundTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        print("🛑 Background tasks cancelled")
    }
}

#else
// macOS, watchOS - use Timer
class BackgroundUpdateManager {
    static let shared = BackgroundUpdateManager()

    private var timer: Timer?

    private init() {}

    func registerBackgroundTasks() {
        #if os(macOS)
        print("✅ macOS: Using Timer for periodic updates")
        #elseif os(watchOS)
        print("✅ watchOS: Using Timer for periodic updates")
        #endif
    }

    func scheduleBackgroundUpdate() {
        timer?.invalidate()

        // Use Timer for hourly updates
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.performUpdate()
        }
        #if os(macOS)
        print("✅ macOS: Background update scheduled every hour")
        #elseif os(watchOS)
        print("✅ watchOS: Background update scheduled every hour")
        #endif
    }

    private func performUpdate() {
        Task {
            do {
                let historicalService = HistoricalWeatherService.shared
                let lat = 40.7128
                let lon = -74.0060

                let extremes = try await historicalService.fetchHistoricalExtremes(
                    latitude: lat,
                    longitude: lon,
                    days: 5
                )

                #if os(macOS)
                print("✅ macOS background update completed: \(extremes.count) days fetched")
                #elseif os(watchOS)
                print("✅ watchOS background update completed: \(extremes.count) days fetched")
                #endif
            } catch {
                #if os(macOS)
                print("❌ macOS background update failed: \(error)")
                #elseif os(watchOS)
                print("❌ watchOS background update failed: \(error)")
                #endif
            }
        }
    }

    func cancelAllBackgroundTasks() {
        timer?.invalidate()
        timer = nil
        #if os(macOS)
        print("🛑 macOS background tasks cancelled")
        #elseif os(watchOS)
        print("🛑 watchOS background tasks cancelled")
        #endif
    }
}
#endif
