import SwiftUI

struct ContentView: View {
    @StateObject private var navigationCoordinator = NavigationCoordinator()
    @StateObject private var summarizerState = SummarizerStateManager()
    
    var body: some View {
        NavigationStack(path: $navigationCoordinator.navigationPath) {
            HomeView()
                .navigationDestination(for: NavigationDestination.self) { destination in
                    switch destination {
                    case .home:
                        HomeView()
                    case .fromText:
                        FromTextView()
                    case .fromFile:
                        FromFileView()
                    case .result:
                        ResultView()
                    }
                }
        }
        .environmentObject(navigationCoordinator)
        .environmentObject(summarizerState)
    }
}

#Preview {
    ContentView()
}
