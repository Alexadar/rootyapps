//
//  SpaceWeatherView.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import SwiftUI

struct SpaceWeatherView: View {
    let extremes: SpaceWeatherExtremes?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("SPACE WEATHER EXTREMES")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .padding(.bottom, 4)

            if let extremes = extremes {
                Divider()

                // K-Index (Geomagnetic Activity)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                        Text("Geomagnetic Activity")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    if let kIndex = extremes.currentKIndex {
                        Text(String(format: "K-Index: %.1f", kIndex))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(kIndexColor(for: kIndex))

                        Text(extremes.getKIndexDescription())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(kIndex >= 5 ? .red : .green)
                    } else {
                        Text("K-Index: --")
                            .font(.system(size: 32, weight: .bold))
                    }

                    // Aurora probability indicator
                    if let kIndex = extremes.currentKIndex, kIndex >= 5 {
                        HStack {
                            Image(systemName: "moon.stars.fill")
                                .foregroundColor(.green)
                            Text("Aurora Possible!")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        .padding(6)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                }

                Divider()

                // Solar Wind
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "wind")
                            .foregroundColor(.yellow)
                        Text("Solar Wind")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    if let windSpeed = extremes.solarWindSpeed {
                        Text(String(format: "%.0f km/s", windSpeed))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(solarWindColor(for: windSpeed))

                        Text(getSolarWindStatus(for: windSpeed))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("-- km/s")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                }

                Divider()

                // Solar Flares
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.red)
                        Text("Solar Flares")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    Text(extremes.getFlareDescription())
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(flareColor(extremes: extremes))

                    if let flare = extremes.latestFlare {
                        if let classType = flare.classType {
                            Text("Class: \(classType)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let peakTime = flare.peakTime {
                            Text("Peak: \(formatDate(peakTime))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Divider()

                // Extreme Badge
                if extremes.isExtreme {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("ELEVATED SPACE WEATHER")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }

                // Last Update
                Text("Updated: \(extremes.lastUpdate.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)

            } else {
                Text("Loading space weather data...")
                    .foregroundColor(.secondary)
                    .padding()
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Helper Functions
    private func kIndexColor(for kIndex: Double) -> Color {
        switch kIndex {
        case 0..<4: return .green
        case 4..<5: return .yellow
        case 5..<7: return .orange
        default: return .red
        }
    }

    private func solarWindColor(for speed: Double) -> Color {
        switch speed {
        case 0..<400: return .green
        case 400..<500: return .yellow
        case 500..<600: return .orange
        default: return .red
        }
    }

    private func getSolarWindStatus(for speed: Double) -> String {
        switch speed {
        case 0..<350: return "Slow"
        case 350..<450: return "Normal"
        case 450..<550: return "Elevated"
        default: return "High Speed Stream"
        }
    }

    private func flareColor(extremes: SpaceWeatherExtremes) -> Color {
        let description = extremes.getFlareDescription()
        if description.contains("X-Class") {
            return .red
        } else if description.contains("M-Class") {
            return .orange
        } else if description.contains("C-Class") {
            return .yellow
        }
        return .secondary
    }

    private func formatDate(_ dateString: String) -> String {
        // Simple formatting - in production you'd parse properly
        return dateString
    }
}

#Preview {
    SpaceWeatherView(extremes: SpaceWeatherExtremes(
        currentKIndex: 6.5,
        kIndexStatus: "Storm",
        solarWindSpeed: 650.0,
        latestFlare: SolarFlareEvent(
            beginTime: "2025-11-06T10:00:00Z",
            peakTime: "2025-11-06T10:30:00Z",
            endTime: "2025-11-06T11:00:00Z",
            classType: "M5.2",
            sourceLocation: "N15W20"
        ),
        flareIntensity: "Strong",
        lastUpdate: Date()
    ))
    .padding()
}
