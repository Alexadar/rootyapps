//
//  eartharound_swiftApp.swift
//  eartharound.swift
//
//  Solar + geomagnetic space-weather tracker. Oracle-validated, ad-free, buy-once.
//

import SwiftUI

@main
struct eartharound_swiftApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AlertNotifier.start()
        BackgroundUpdateManager.register()
        #if os(iOS)
        WatchSync.shared.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { BackgroundUpdateManager.schedule() }
                }
        }
        #if os(macOS)
        .defaultSize(width: 720, height: 900)
        #endif
    }
}
