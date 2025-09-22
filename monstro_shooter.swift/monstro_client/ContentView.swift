import SwiftUI
import SpriteKit

/// Replaced RealityKit example with a simple SpriteKit host for macOS.
/// Shows GameScene (WASD movement + mouse aiming/shooting).
struct ContentView: View {
    var scene: SKScene {
        let s = GameScene(size: CGSize(width: 1024, height: 768))
        s.scaleMode = .resizeFill
        return s
    }

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
            .onAppear {
                #if os(macOS)
                NSApp.mainWindow?.acceptsMouseMovedEvents = true
                #endif
            }
    }
}

#Preview {
    ContentView()
}
