//
//  SpaceWeatherPanel.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import SwiftUI

struct SpaceWeatherPanel: View {
    let title: String
    let extremes: SpaceWeatherExtremes?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            if let space = extremes {
                FlowLayout(spacing: 8) {
                    if let kp = space.currentKIndex, kp >= 5.0 {
                        SpaceEventBadge(type: .geomagnetic, value: kp)
                    }
                    if let speed = space.solarWindSpeed, speed > 500 {
                        SpaceEventBadge(type: .solarWind, value: speed)
                    }
                    if let flare = space.latestFlare?.classType {
                        SpaceEventBadge(type: .flare, label: flare)
                    }
                }
            } else {
                Text("No space weather extremes")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct SpaceEventBadge: View {
    enum SpaceEventType {
        case geomagnetic
        case solarWind
        case flare
    }

    let type: SpaceEventType
    var value: Double?
    var label: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(icon)
                .font(.system(size: 24))
            Text(displayLabel)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundColor)
        )
        .foregroundColor(.white)
    }

    var icon: String {
        switch type {
        case .geomagnetic: return "🌍"
        case .solarWind: return "🌬️"
        case .flare: return "☀️"
        }
    }

    var displayLabel: String {
        if let lbl = label {
            return lbl
        }
        if let val = value {
            switch type {
            case .geomagnetic: return "Kp \(String(format: "%.1f", val))"
            case .solarWind: return "\(String(format: "%.0f", val))km/s"
            case .flare: return ""
            }
        }
        return ""
    }

    var backgroundColor: Color {
        switch type {
        case .geomagnetic: return .green
        case .solarWind: return .orange
        case .flare: return .yellow
        }
    }
}
