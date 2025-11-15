//
//  IOSContentView.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import SwiftUI

#if os(iOS)
struct IOSContentView: View {
    @StateObject private var viewModel = ExtremesViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Today's Extremes
                    if let today = viewModel.todayExtremes {
                        ExtremesPanel(title: "Today", extremes: today)
                    }

                    // Yesterday's Extremes
                    if let yesterday = viewModel.yesterdayExtremes {
                        ExtremesPanel(title: "Yesterday", extremes: yesterday)
                    }

                    if viewModel.isLoading {
                        ProgressView("Loading extremes...")
                            .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("Extremes")
            .navigationBarTitleDisplayMode(.large)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.1),
                        Color.purple.opacity(0.1)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
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
