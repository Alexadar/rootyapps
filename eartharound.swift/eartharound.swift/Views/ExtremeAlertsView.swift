//
//  ExtremeAlertsView.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import SwiftUI

struct ExtremeAlertsView: View {
    let events: [ExtremeEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.red)
                Text("ACTIVE EXTREMES")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .padding(.bottom, 4)

            Divider()

            ForEach(events) { event in
                HStack(spacing: 12) {
                    Text(event.severity.rawValue)
                        .font(.title)

                    Image(systemName: event.icon)
                        .font(.title3)
                        .foregroundColor(severityColor(event.severity))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.description)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(event.value)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(8)
                .background(severityColor(event.severity).opacity(0.1))
                .cornerRadius(8)
            }
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

    private func severityColor(_ severity: ExtremeSeverity) -> Color {
        switch severity {
        case .warning: return .orange
        case .danger: return .red
        case .extreme: return .purple
        }
    }
}

#Preview {
    ExtremeAlertsView(events: [
        ExtremeEvent(
            type: .temperature,
            severity: .extreme,
            value: "38.5°C",
            description: "Extreme Heat",
            icon: "flame.fill"
        ),
        ExtremeEvent(
            type: .wind,
            severity: .danger,
            value: "85 km/h",
            description: "Storm Force Winds",
            icon: "tornado"
        ),
        ExtremeEvent(
            type: .kIndex,
            severity: .warning,
            value: "5.2",
            description: "Minor Geomagnetic Storm",
            icon: "sparkles"
        )
    ])
    .padding()
}
