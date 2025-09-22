import SwiftUI

struct ContentView: View {
    @EnvironmentObject var gameEngine: GameEngine

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            switch gameEngine.gameState {
            case .menu:
                MenuView()
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
            case .playing, .paused:
                GameView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .leading)
                    ))
            case .gameOver:
                GameOverView()
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: gameEngine.gameState)
    }
}

struct GameOverView: View {
    @EnvironmentObject var gameEngine: GameEngine

    var body: some View {
        VStack(spacing: 30) {
            Text("💀 Game Over 💀")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.red)

            Text("Final Score: \(gameEngine.score)")
                .font(.system(size: 32, weight: .medium, design: .rounded))
                .foregroundColor(.yellow)

            Text("Level: \(gameEngine.currentLevel)")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundColor(.white)

            HStack(spacing: 40) {
                Button(action: {
                    gameEngine.restartGame()
                }) {
                    Label("Play Again", systemImage: "arrow.clockwise")
                        .font(.system(size: 20, weight: .semibold))
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                }

                Button(action: {
                    gameEngine.returnToMenu()
                }) {
                    Label("Menu", systemImage: "house")
                        .font(.system(size: 20, weight: .semibold))
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                }
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(GameEngine())
}