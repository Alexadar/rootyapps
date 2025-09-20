//
//  GameOverView.swift
//  froggo.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SwiftUI

struct GameOverView: View {
    @Binding var gameState: GameState
    let score: Int
    @State private var highScore: Int = UserDefaults.standard.integer(forKey: "highScore")
    @State private var isNewHighScore: Bool = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.red.opacity(0.8), Color.orange.opacity(0.6)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Game Over Title
                Text("GAME OVER")
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 5, x: 2, y: 2)
                
                // Sad frog emoji
                Text("💀")
                    .font(.system(size: 60))
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 2, y: 2)
                
                // Score display
                VStack(spacing: 15) {
                    Text("Your Score")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text("\(score)")
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .foregroundColor(.yellow)
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 2, y: 2)
                    
                    if isNewHighScore {
                        Text("🎉 NEW HIGH SCORE! 🎉")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.yellow)
                            .shadow(color: .black.opacity(0.3), radius: 3, x: 1, y: 1)
                    } else {
                        Text("High Score: \(highScore)")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.3))
                )
                
                // Buttons
                VStack(spacing: 15) {
                    // Play Again Button
                    Button(action: {
                        gameState = .playing
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .font(.title2)
                            Text("Play Again")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(width: 200, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color.green)
                                .shadow(color: .black.opacity(0.3), radius: 5, x: 2, y: 2)
                        )
                    }
                    .buttonStyle(PressedButtonStyle())
                    
                    // Main Menu Button
                    Button(action: {
                        gameState = .menu
                    }) {
                        HStack {
                            Image(systemName: "house.fill")
                                .font(.title2)
                            Text("Main Menu")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(width: 200, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color.blue)
                                .shadow(color: .black.opacity(0.3), radius: 5, x: 2, y: 2)
                        )
                    }
                    .buttonStyle(PressedButtonStyle())
                }
                
                Spacer()
            }
            .padding()
        }
        .onAppear {
            checkHighScore()
            SoundManager.shared.playGameOverSound()
        }
    }
    
    private func checkHighScore() {
        highScore = UserDefaults.standard.integer(forKey: "highScore")
        if score > highScore {
            isNewHighScore = true
            UserDefaults.standard.set(score, forKey: "highScore")
            highScore = score
        }
    }
}
