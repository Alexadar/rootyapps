import SwiftUI

@main
struct ProducerTycoonApp: App {
    @StateObject private var game = GameViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(game)
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 560)
                #endif
        }
    }
}
