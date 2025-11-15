//
//  VisionOSContentView.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 11.11.2025.
//

import SwiftUI

#if os(visionOS)
struct VisionOSContentView: View {
    @StateObject private var viewModel = ExtremesViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.orange)
                            Text("Extremes")
                                .font(.system(size: 50, weight: .bold))
                        }
                        Text("Today & Yesterday")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)

                    // Today's Extremes
                    if let today = viewModel.todayExtremes {
                        ExtremesPanel(title: "Today", extremes: today)
                            .padding(.horizontal, 60)
                    }

                    // Yesterday's Extremes
                    if let yesterday = viewModel.yesterdayExtremes {
                        ExtremesPanel(title: "Yesterday", extremes: yesterday)
                            .padding(.horizontal, 60)
                    }

                    // Error Message
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.title3)
                            .foregroundColor(.red)
                            .padding(32)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal, 60)
                    }

                    if viewModel.isLoading {
                        ProgressView("Loading extremes...")
                            .font(.title3)
                            .padding(40)
                    }

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Earth Extremes")
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
