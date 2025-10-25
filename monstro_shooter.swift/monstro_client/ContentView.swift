import SwiftUI
import SpriteKit

struct ContentView: View {
    @State private var showGame = false

    var body: some View {
        if showGame {
            GameView()
        } else {
            AnimatedMainMenuView(onPlayTapped: {
                showGame = true
            })
        }
    }
}

// MARK: - Animated Main Menu (simple static background)
struct AnimatedMainMenuView: View {
    let onPlayTapped: () -> Void

    var body: some View {
        ZStack {
            // Simple black background instead of animated scene
            Color.black
                .ignoresSafeArea()
                .transition(.opacity)

            // Overlay UI (Play button)
            VStack {
                Spacer()
                Button(action: onPlayTapped) {
                    Text("PLAY")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 60)
                        .padding(.vertical, 20)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.red.opacity(0.9)))
                        .shadow(radius: 8)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 60)
            }
        }
    }
}

// MARK: - Game View (full game)
struct GameView: View {
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
