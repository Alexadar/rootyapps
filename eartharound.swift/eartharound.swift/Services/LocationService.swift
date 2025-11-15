//
//  LocationService.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import Foundation
import CoreLocation
import MapKit
import Combine

@MainActor
class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var locationName: String = "Current Location"

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            currentLocation = location.coordinate

            do {
                let localSearchCompleter = MKLocalSearchCompleter()
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = "\(location.coordinate.latitude),\(location.coordinate.longitude)"
                request.resultTypes = .address

                let search = MKLocalSearch(request: request)
                let response = try await search.start()

                if let mapItem = response.mapItems.first {
                    locationName = mapItem.placemark.locality ?? mapItem.placemark.administrativeArea ?? "Current Location"
                }
            } catch {
                print("❌ Geocoding error: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
    }
}
