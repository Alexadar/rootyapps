//
//  MainMenuView.swift
//  froggo.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SwiftUI

struct MainMenuView: View {
    @State private var isMuted = UserDefaults.standard.bool(forKey: "mute")
    @Binding var gameState: GameState
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.cyan, Color.blue]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Game Title
                Text("FROGGO")
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 2, y: 2)
                
                // Frog emoji or icon
                Text("🐸")
                    .font(.system(size: 80))
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 2, y: 2)
                
                VStack(spacing: 20) {
                    // Start Game Button
                    Button(action: {
                        gameState = .playing
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                                .font(.title2)
                            Text("Start Game")
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
                    
                    // Mute/Unmute Button
                    Button(action: {
                        isMuted.toggle()
                        UserDefaults.standard.set(isMuted, forKey: "mute")
                        SoundManager.shared.isMuted = isMuted
                    }) {
                        HStack {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.2.fill")
                                .font(.title2)
                            Text(isMuted ? "Unmute" : "Mute")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(width: 200, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color.orange)
                                .shadow(color: .black.opacity(0.3), radius: 5, x: 2, y: 2)
                        )
                    }
                    .buttonStyle(PressedButtonStyle())
                }
                
                Spacer()
                
                // Instructions
                VStack(spacing: 10) {
                    Text("How to Play:")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("• Drag to aim your jump")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text("• Land on buildings to progress")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text("• Collect flies for super jumps")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text("• Don't fall!")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color.black.opacity(0.3))
                )
            }
            .padding()
        }
        .onAppear {
            isMuted = UserDefaults.standard.bool(forKey: "mute")
            SoundManager.shared.isMuted = isMuted
        }
    }
}

// Custom button style for pressed effect
struct PressedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

enum GameState {
    case menu
    case playing
    case gameOver
}
