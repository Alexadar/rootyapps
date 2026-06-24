//
//  TVOSContentView.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 11.11.2025.
//

import SwiftUI

#if os(tvOS)
struct TVOSContentView: View {
    @StateObject private var viewModel = ExtremesViewModel()

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(0.15),
                    Color.purple.opacity(0.15)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.orange)
                            Text("Extremes")
                                .font(.system(size: 60, weight: .bold))
                        }
                        Text("Today & Yesterday")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 60)

                    // Today's Extremes
                    if let today = viewModel.todayExtremes {
                        ExtremesPanel(title: "Today", extremes: today)
                            .padding(.horizontal, 80)
                    }

                    // Yesterday's Extremes
                    if let yesterday = viewModel.yesterdayExtremes {
                        ExtremesPanel(title: "Yesterday", extremes: yesterday)
                            .padding(.horizontal, 80)
                    }

                    if let error = viewModel.error {
                        ErrorBanner(message: error.shortMessage) {
                            Task { await viewModel.fetchAllExtremes() }
                        }
                        .padding(.horizontal, 80)
                    }

                    if viewModel.isLoading {
                        ProgressView("Loading extremes...")
                            .font(.title3)
                            .padding(40)
                    }

                    Spacer(minLength: 60)
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
#endif
