//
//  WatchContentView.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import SwiftUI

#if os(watchOS)
struct WatchContentView: View {
    @StateObject private var viewModel = ExtremesViewModel()

    var body: some View {
        TabView {
            WatchExtremesCard(
                title: "Today",
                extremes: viewModel.todayExtremes,
                error: viewModel.error
            )
            .containerBackground(.blue.gradient, for: .tabView)

            WatchExtremesCard(
                title: "Yesterday",
                extremes: viewModel.yesterdayExtremes,
                error: viewModel.error
            )
            .containerBackground(.purple.gradient, for: .tabView)
        }
        .tabViewStyle(.verticalPage)
        .task {
            await viewModel.fetchAllExtremes()
        }
    }
}

struct WatchExtremesCard: View {
    let title: String
    let extremes: DailyExtremes?
    let error: FetchError?
    @State private var selectedEvent: AggregatedEvent?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Title
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top, 8)

                if let extremes = extremes {
                    if extremes.aggregated.isEmpty {
                        Text("No extremes")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.vertical, 20)
                    } else {
                        ForEach(extremes.aggregated) { event in
                            WatchEventBadge(event: event)
                                .onTapGesture {
                                    selectedEvent = event
                                }
                        }
                    }
                } else if let error = error {
                    Text(error.shortMessage)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.vertical, 20)
                } else {
                    ProgressView()
                        .tint(.white)
                        .padding(.vertical, 20)
                }
            }
            .padding(.horizontal, 4)
        }
        .sheet(item: $selectedEvent) { event in
            WatchEventDetail(event: event)
        }
    }
}

struct WatchEventBadge: View {
    let event: AggregatedEvent

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(event.icon)
                    .font(.title2)
                Text(event.shortDisplayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                if event.count > 1 {
                    Text("x\(event.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                }
            }
            HStack {
                Text(event.formattedValue)
                    .font(.caption2)
                Spacer()
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(event.themeColor.opacity(0.8))
        )
        .foregroundColor(.white)
    }
}

struct WatchEventDetail: View {
    let event: AggregatedEvent
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var eventConfig: ExtremeTypeConfig? {
        SettingsLoader.shared.settings?.extremeTypes.first { $0.id == event.type.rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(event.icon)
                    .font(.system(size: 50))

                Text(event.displayName)
                    .font(.headline)

                // Description
                if let config = eventConfig {
                    Text(config.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Peak")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(event.formattedValue)
                            .font(.body)
                            .fontWeight(.semibold)
                    }

                    if event.count > 1 {
                        HStack {
                            Text("Count")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(event.count)")
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                    }

                    if let config = eventConfig {
                        if let rangeDesc = config.rangeDescription {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Trigger")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(rangeDesc)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let typicalRange = config.typicalRange {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Expected")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(typicalRange)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                // Severity explanation
                if let explanation = event.severityExplanation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Context")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Text(explanation)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                    )
                }

                Button("Close") {
                    dismiss()
                }
                .font(.caption)
                .padding(.top, 8)
            }
            .padding()
        }
    }

}
#endif
