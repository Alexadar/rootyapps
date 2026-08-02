import SwiftUI

/// Video background layer for main menu with alternating videos and crossfade transitions
struct MainMenuVideoLayer: View {
    var body: some View {
        VideoPlayerPlatformView()
            .ignoresSafeArea()
    }
}
