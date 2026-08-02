 //
//  ContentView.swift
//  typingmill.swift
//
//  Created by Oleksandr Koreniuk on 20.09.2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        #if os(macOS)
        MacContentView()
        #else
        IOSContentView()
        #endif
    }
}

#Preview {
    ContentView()
}
