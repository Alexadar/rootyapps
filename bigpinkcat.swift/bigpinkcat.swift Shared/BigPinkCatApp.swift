//
//  BigPinkCatApp.swift
//  bigpinkcat.swift
//
//  SwiftUI App entry point - replaces UIKit/AppKit AppDelegate pattern
//

import SwiftUI
import SpriteKit

@main
struct BigPinkCatApp: App {
    var body: some Scene {
        WindowGroup {
            GameContentView()
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 600, height: 900)
        #endif
    }
}
