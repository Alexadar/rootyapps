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

// MARK: - Animated Main Menu (uses GameScene + AIInput)
struct AnimatedMainMenuView: View {
    let onPlayTapped: () -> Void

    // Create and configure the SpriteKit scene with AI input once and keep it alive.
    private let menuScene: GameScene
    private let aiInput: AIInput

    init(onPlayTapped: @escaping () -> Void) {
        self.onPlayTapped = onPlayTapped
        let s = GameScene(size: CGSize(width: 1024, height: 768))
        s.scaleMode = .resizeFill
        // Attach AI input to the scene so the player is scripted in the menu and keep references.
        let ai = AIInput(scene: s)
        s.externalInput = ai
        self.menuScene = s
        self.aiInput = ai
    }

    var body: some View {
        ZStack {
            // SpriteKit scene as animated background
            SpriteView(scene: menuScene)
                .ignoresSafeArea()
                .transition(.opacity)
                .onAppear {
                    // Start AI-driven menu scripting once the scene is presented
                    menuScene.startMenuScripting()
                }

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
