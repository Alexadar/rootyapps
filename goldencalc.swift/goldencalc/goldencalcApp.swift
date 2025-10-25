//
//  goldencalcApp.swift
//  goldencalc
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SwiftUI

@main
struct goldencalcApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 430, height: 932)
        .windowResizability(.contentSize)
        #endif
    }
}
