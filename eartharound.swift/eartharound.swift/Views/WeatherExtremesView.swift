//
//  WeatherExtremesView.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import SwiftUI

struct WeatherExtremesView: View {
    let extremes: WeatherExtremes?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "cloud.sun.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("WEATHER EXTREMES")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .padding(.bottom, 4)

            if let extremes = extremes {
                // Location
                Text(extremes.location)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Divider()

                // Temperature
                HStack {
                    VStack(alignment: .leading) {
                        Text("Temperature")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let temp = extremes.currentTemp {
                            Text(String(format: "%.1f°C", temp))
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(tempColor(for: temp))
                        } else {
                            Text("--")
                                .font(.system(size: 36, weight: .bold))
                        }
                        Text(extremes.getTempStatus())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(extremes.isExtreme ? .red : .green)
                    }
                    Spacer()
                }

                // Feels Like
                if let feelsLike = extremes.feelsLike {
                    HStack {
                        Text("Feels like:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f°C", feelsLike))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }

                Divider()

                // Wind
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "wind")
                            .foregroundColor(.cyan)
                        Text("Wind")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    if let windSpeed = extremes.windSpeed {
                        Text(String(format: "%.1f km/h", windSpeed))
                            .font(.title3)
                            .fontWeight(.bold)
                        Text(extremes.getWindStatus())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let gusts = extremes.windGusts, gusts > 0 {
                        Text("Gusts: \(String(format: "%.1f km/h", gusts))")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Divider()

                // Precipitation & Humidity
                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: "drop.fill")
                                .foregroundColor(.blue)
                            Text("Rain")
                                .font(.caption)
                        }
                        if let precip = extremes.precipitation {
                            Text(String(format: "%.1f mm", precip))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        } else {
                            Text("0.0 mm")
                                .font(.subheadline)
                        }
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: "humidity")
                                .foregroundColor(.teal)
                            Text("Humidity")
                                .font(.caption)
                        }
                        if let humidity = extremes.humidity {
                            Text("\(humidity)%")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        } else {
                            Text("--")
                                .font(.subheadline)
                        }
                    }
                }

                // Extreme Badge
                if extremes.isExtreme {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("EXTREME CONDITIONS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }

            } else {
                Text("Loading weather data...")
                    .foregroundColor(.secondary)
                    .padding()
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #elseif os(watchOS) || os(tvOS)
        .background(Color.black.opacity(0.3))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private func tempColor(for temp: Double) -> Color {
        switch temp {
        case ..<0: return .blue
        case 0..<10: return .cyan
        case 10..<25: return .green
        case 25..<35: return .orange
        default: return .red
        }
    }
}

#Preview {
    WeatherExtremesView(extremes: WeatherExtremes(
        currentTemp: 38.5,
        feelsLike: 42.0,
        windSpeed: 65.0,
        windGusts: 85.0,
        precipitation: 12.5,
        humidity: 78,
        location: "New York",
        lastUpdate: Date()
    ))
    .padding()
}
