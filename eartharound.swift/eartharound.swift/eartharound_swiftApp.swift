//
//  eartharound_swiftApp.swift
//  eartharound.swift
//
//  Created by Oleksandr Koreniuk on 06.11.2025.
//

import SwiftUI

@main
struct eartharound_swiftApp: App {
    init() {
        // Register background tasks on launch
        BackgroundUpdateManager.shared.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Schedule first background update
                    BackgroundUpdateManager.shared.scheduleBackgroundUpdate()
                }
        }
    }
}
