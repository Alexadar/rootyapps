import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    var body: some View {
        Group {
            #if os(macOS)
            MacOSContentView()
            #else
            IOSContentView()
            #endif
        }
    }
}

// iOS/Other platforms content view
#if !os(macOS)
struct IOSContentView: View {
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
#endif

#Preview {
    ContentView()
}
