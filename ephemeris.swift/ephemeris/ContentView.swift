import SwiftUI

struct ContentView: View {
    var body: some View {
        #if os(macOS)
        MacOSContentView()
        #elseif os(iOS)
        IOSContentView()
        #else
        Text("Unsupported platform")
        #endif
    }
}
