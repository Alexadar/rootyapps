//
//  EventDetailView.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import SwiftUI

struct EventDetailView: View {
    let event: AggregatedEvent
    let onDismiss: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var eventConfig: ExtremeTypeConfig? {
        SettingsLoader.shared.settings?.extremeTypes.first { $0.id == event.type.rawValue }
    }

    var body: some View {
        ZStack {
            // Background overlay - adapts to color scheme
            Color.black.opacity(colorScheme == .dark ? 0.4 : 0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            // Detail Card
            VStack(spacing: 24) {
                // Header
                HStack {
                    Text("Event Details")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }

                // Icon
                Text(event.icon)
                    .font(.system(size: 80))

                // Event Type
                VStack(spacing: 8) {
                    Text("Type")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(event.displayName)
                        .font(.title)
                        .fontWeight(.semibold)

                    // Description
                    if let config = eventConfig {
                        Text(config.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }

                Divider()

                // Details Grid
                VStack(spacing: 16) {
                    DetailRow(
                        label: "Peak Value",
                        value: event.formattedValue
                    )

                    if event.count > 1 {
                        DetailRow(
                            label: "Occurrences",
                            value: "\(event.count)"
                        )
                    }

                    // Range information from settings
                    if let config = eventConfig {
                        if let rangeDesc = config.rangeDescription {
                            DetailRow(
                                label: "Trigger",
                                value: rangeDesc
                            )
                        }

                        if let typicalRange = config.typicalRange {
                            DetailRow(
                                label: "Expected Range",
                                value: typicalRange
                            )
                        }
                    }
                }

                // Severity explanation
                if let explanation = event.severityExplanation {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Severity Context")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        Text(explanation)
                            .font(.body)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                    )
                    .padding(.horizontal, 32)
                }

                // Color Badge
                RoundedRectangle(cornerRadius: 8)
                    .fill(event.themeColor)
                    .frame(height: 4)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
                    .shadow(color: colorScheme == .dark ? Color.black.opacity(0.5) : Color.black.opacity(0.2), radius: 20)
            )
            .padding(40)
        }
    }

}

struct DetailRow: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
        )
    }
}
