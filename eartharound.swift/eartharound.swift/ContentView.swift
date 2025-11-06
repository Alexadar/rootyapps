//
//  ContentView.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ExtremesViewModel()
    private let extremeManager = ExtremeManager.shared

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.1),
                        Color.purple.opacity(0.1)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Header
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "globe.americas.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.blue)
                                Text("Earth Around")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                            }
                            Text("Local Extremes Tracker")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 16)

                        // Active Extremes Alert Panel
                        if extremeManager.hasActiveExtremes(weather: viewModel.weatherExtremes, space: viewModel.spaceExtremes) {
                            ExtremeAlertsView(
                                events: extremeManager.getAllExtremes(
                                    weather: viewModel.weatherExtremes,
                                    space: viewModel.spaceExtremes
                                )
                            )
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        }

                        // Split Layout - 50/50 columns
                        if geometry.size.width > 700 {
                            // Side by side for larger screens
                            HStack(alignment: .top, spacing: 16) {
                                // Left Column - Weather
                                WeatherExtremesView(extremes: viewModel.weatherExtremes)
                                    .frame(maxWidth: .infinity)

                                // Right Column - Space Weather
                                SpaceWeatherView(extremes: viewModel.spaceExtremes)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal)
                        } else {
                            // Stacked for smaller screens (iPhone, Apple Watch)
                            VStack(spacing: 16) {
                                // Top - Weather
                                WeatherExtremesView(extremes: viewModel.weatherExtremes)

                                // Bottom - Space Weather
                                SpaceWeatherView(extremes: viewModel.spaceExtremes)
                            }
                            .padding(.horizontal)
                        }

                        // Error Message
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                                .padding()
                        }

                        if viewModel.isLoading {
                            ProgressView("Loading extremes...")
                                .padding()
                        }

                        Spacer(minLength: 20)
                    }
                }
            }
        }
        .task {
            await viewModel.fetchAllExtremes()
            viewModel.startAutoRefresh()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
    }
}

#Preview {
    ContentView()
}
