//
//  ContentView.swift
//  froggo.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SwiftUI

struct ContentView: View {
    @State private var gameState: GameState = .menu
    @State private var finalScore: Int = 0

    var body: some View {
        ZStack {
            switch gameState {
            case .menu:
                MainMenuView(gameState: $gameState)
                    .transition(.opacity)

            case .playing:
                GameView(gameState: $gameState, finalScore: $finalScore)
                    .transition(.opacity)

            case .gameOver:
                GameOverView(gameState: $gameState, score: finalScore)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: gameState)
    }
}

#Preview {
    ContentView()
}
