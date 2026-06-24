import SwiftUI

#if os(iOS)
struct IOSContentView: View {
    @StateObject private var viewModel = ExtremesViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if let error = viewModel.error {
                        ErrorBanner(message: error.shortMessage) {
                            Task { await viewModel.fetchAllExtremes() }
                        }
                    }

                    if let today = viewModel.todayExtremes {
                        ExtremesPanel(title: "Today", extremes: today)
                    }

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
            .refreshable {
                await viewModel.fetchAllExtremes()
            }
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
