import SwiftUI
import SpriteKit
#if os(macOS)
import AppKit
#endif

struct GameView: View {
    @EnvironmentObject var gameEngine: GameEngine
    @StateObject private var inputHandler = InputHandler()
    #if os(macOS)
    @State private var localMonitor: Any?
    #endif

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                SpriteView(scene: makeScene(size: geometry.size))
                    .ignoresSafeArea()
                    .onAppear {
                        inputHandler.gameEngine = gameEngine
                    }

                VStack {
                    HUDView()
                        .padding()

                    Spacer()

                    #if os(iOS)
                    if gameEngine.controlType == .dpad {
                        DPadView(inputHandler: inputHandler)
                            .frame(width: 150, height: 150)
                            .padding(.bottom, 50)
                            .opacity(0.8)
                    }
                    #endif
                }

                if gameEngine.gameState == .paused {
                    PauseOverlay()
                }
            }
            #if os(iOS)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if gameEngine.controlType == .swipe {
                            inputHandler.handleSwipe(value)
                        }
                    }
            )
            #endif
            #if os(macOS)
            .onAppear {
                // Ensure engine is wired and install a key monitor for arrow keys + WASD.
                inputHandler.gameEngine = gameEngine
                // Try a local monitor first (we must RETURN the event to avoid swallowing it).
                localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    switch event.keyCode {
                    case 123: // left arrow
                        inputHandler.handleDirection(.left)
                    case 124: // right arrow
                        inputHandler.handleDirection(.right)
                    case 125: // down arrow
                        inputHandler.handleDirection(.down)
                    case 126: // up arrow
                        inputHandler.handleDirection(.up)
                    default:
                        if let chars = event.charactersIgnoringModifiers?.lowercased() {
                            if chars.contains("a") { inputHandler.handleDirection(.left) }
                            else if chars.contains("d") { inputHandler.handleDirection(.right) }
                            else if chars.contains("s") { inputHandler.handleDirection(.down) }
                            else if chars.contains("w") { inputHandler.handleDirection(.up) }
                        }
                    }
                    return event
                }
                // If local monitor couldn't be installed (rare), install a global monitor as fallback.
                if localMonitor == nil {
                    localMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                        switch event.keyCode {
                        case 123:
                            inputHandler.handleDirection(.left)
                        case 124:
                            inputHandler.handleDirection(.right)
                        case 125:
                            inputHandler.handleDirection(.down)
                        case 126:
                            inputHandler.handleDirection(.up)
                        default:
                            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                                if chars.contains("a") { inputHandler.handleDirection(.left) }
                                else if chars.contains("d") { inputHandler.handleDirection(.right) }
                                else if chars.contains("s") { inputHandler.handleDirection(.down) }
                                else if chars.contains("w") { inputHandler.handleDirection(.up) }
                            }
                        }
                    }
                }
            }
            .onDisappear {
                if let monitor = localMonitor {
                    NSEvent.removeMonitor(monitor)
                    localMonitor = nil
                }
            }
            #endif
        }
    }

    func makeScene(size: CGSize) -> GameScene {
        let scene = GameScene(size: size)
        scene.scaleMode = .resizeFill
        scene.gameEngine = gameEngine
        scene.inputHandler = inputHandler
        return scene
    }
}

struct HUDView: View {
    @EnvironmentObject var gameEngine: GameEngine

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Text("Score:")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(gameEngine.score)")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.yellow)
                }

                HStack(spacing: 5) {
                    Text("Lives:")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    HStack(spacing: 3) {
                        ForEach(0..<gameEngine.lives, id: \.self) { _ in
                            Text("❤️")
                                .font(.system(size: 20))
                        }
                        ForEach(0..<(3 - gameEngine.lives), id: \.self) { _ in
                            Text("🖤")
                                .font(.system(size: 20))
                        }
                    }
                }
            }
            .padding(15)
            .background(Color.black.opacity(0.7))
            .cornerRadius(15)

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 5) {
                    Text("Level:")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(gameEngine.currentLevel)")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                }

                Button(action: {
                    gameEngine.togglePause()
                }) {
                    Image(systemName: gameEngine.gameState == .paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.blue.opacity(0.7))
                        .cornerRadius(10)
                }
            }
            .padding(15)
            .background(Color.black.opacity(0.7))
            .cornerRadius(15)
        }
    }
}

struct PauseOverlay: View {
    @EnvironmentObject var gameEngine: GameEngine

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Text("⏸️ Paused")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                VStack(spacing: 20) {
                    Button(action: {
                        gameEngine.togglePause()
                    }) {
                        Label("Resume", systemImage: "play.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .frame(width: 200, height: 50)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                    }

                    Button(action: {
                        gameEngine.restartGame()
                    }) {
                        Label("Restart", systemImage: "arrow.clockwise")
                            .font(.system(size: 24, weight: .semibold))
                            .frame(width: 200, height: 50)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                    }

                    Button(action: {
                        gameEngine.returnToMenu()
                    }) {
                        Label("Menu", systemImage: "house")
                            .font(.system(size: 24, weight: .semibold))
                            .frame(width: 200, height: 50)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(15)
                    }
                }
            }
            .padding()
            .background(Color.black.opacity(0.9))
            .cornerRadius(20)
        }
    }
}

#if os(iOS)
struct DPadView: View {
    @ObservedObject var inputHandler: InputHandler

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.3))
                .frame(width: 150, height: 150)

            VStack(spacing: 0) {
                Button(action: {
                    inputHandler.handleDirection(.up)
                }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                }

                HStack(spacing: 0) {
                    Button(action: {
                        inputHandler.handleDirection(.left)
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                    }

                    Spacer()
                        .frame(width: 50)

                    Button(action: {
                        inputHandler.handleDirection(.right)
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                    }
                }

                Button(action: {
                    inputHandler.handleDirection(.down)
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                }
            }
        }
    }
}
#endif

#Preview {
    GameView()
        .environmentObject(GameEngine())
}
