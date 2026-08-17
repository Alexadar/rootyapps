import SwiftUI

// One app, three canvases. Same four sections, same order, same symbols,
// same vocabulary everywhere. Only the container adapts:
// iPhone: TabView · iPad: TabView or sidebar · Mac: sidebar.
// A month-long iPhone user opening the Mac app should be surprised by nothing.
@main
struct GridScanApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Library", systemImage: "books.vertical") { LibraryView(documents: SampleData.documents) }
            Tab("Search & Ask", systemImage: "magnifyingglass") { SearchAskView(answersAvailable: DeviceCapability.answersAvailable) }
            Tab("Destinations", systemImage: "arrow.up.right.square") { DestinationsView(destinations: SampleData.destinations) }
            Tab("Activity", systemImage: "clock") { ActivityView(events: SampleData.events) }
        }
        // Liquid Glass chrome only — documents and grids stay opaque paper/data.
        // Never .ultraThinMaterial / .regularMaterial / .thinMaterial.
    }
}

// First run asks for nothing: no account, no org, no email.
// The empty Library teaches the ways in.
struct FirstRunView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("GridScan").font(.largeTitle.bold())
            Text("Documents stay on your device and in your iCloud.")
                .foregroundStyle(.secondary)
            Button("Start") {}.buttonStyle(.glassProminent)
        }
    }
}
