//
//  aisixteen_studioApp.swift
//  aisixteen.studio
//
//  Created by Oleksandr Koreniuk on 19.11.2023.
//

import SwiftUI
import FirebaseCore

@main
struct aisixteen_studioApp: App {
    @State private var isLoggedIn = false
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            RouterView()
                .environmentObject(MainProvider(mock: false))
        }
    }
}
