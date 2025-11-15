//
//  ContentView.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        #if os(macOS)
        MacOSContentView()
        #elseif os(iOS)
        IOSContentView()
        #elseif os(watchOS)
        WatchContentView()
        #elseif os(tvOS)
        TVOSContentView()
        #elseif os(visionOS)
        VisionOSContentView()
        #else
        Text("Unsupported platform")
        #endif
    }
}

#Preview {
    ContentView()
}
