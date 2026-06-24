import SwiftUI

#if os(macOS)
struct MacOSContentView: View {
    @StateObject private var viewModel = ExtremesViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let error = viewModel.error {
                        ErrorBanner(message: error.shortMessage) {
                            Task { await viewModel.fetchAllExtremes() }
                        }
                        .padding(.horizontal)
                    }

                    if let today = viewModel.todayExtremes {
                        ExtremesPanel(title: "Today", extremes: today)
                            .padding(.horizontal)
                    }

                    if let yesterday = viewModel.yesterdayExtremes {
                        ExtremesPanel(title: "Yesterday", extremes: yesterday)
                            .padding(.horizontal)
                    }

                    if viewModel.isLoading {
                        ProgressView("Loading extremes...")
                            .padding()
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top, 16)
            }
            .navigationTitle("Extremes")
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
