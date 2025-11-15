//
//  MacOSContentView.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import SwiftUI

#if os(macOS)
struct MacOSContentView: View {
    @StateObject private var viewModel = ExtremesViewModel()

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
                                Image(systemName: "bolt.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.orange)
                                Text("Extremes")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                            }
                            Text("Today & Yesterday")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 16)

                        // Today's Extremes
                        if let today = viewModel.todayExtremes {
                            ExtremesPanel(title: "Today", extremes: today)
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                        }

                        // Yesterday's Extremes
                        if let yesterday = viewModel.yesterdayExtremes {
                            ExtremesPanel(title: "Yesterday", extremes: yesterday)
                                .padding(.horizontal)
                                .padding(.bottom, 8)
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
#endif
