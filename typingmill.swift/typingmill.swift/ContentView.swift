//
//  ContentView.swift
//  typingmill.swift
//
//  Created by Oleksandr Koreniuk on 20.09.2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var typingMill = TypingMill()
    @State private var keyMonitor: Any?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black background
                Color.black
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Difficulty buttons at the top
                    HStack(spacing: 20) {
                        ForEach(1...4, id: \.self) { difficulty in
                            DifficultyButton(
                                difficulty: difficulty,
                                isPressed: typingMill.currentDifficulty == difficulty
                            ) {
                                typingMill.changeDifficulty(difficulty)
                            }
                        }
                    }
                    .padding(.top, 50)
                    
                    Spacer()
                    
                    // Main typing area
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(typingMill.millElements) { element in
                                MillElementView(element: element)
                            }
                        }
                        .padding(.horizontal, geometry.size.width / 2)
                    }
                    .frame(height: 100)
                    .clipped()
                    
                    Spacer()
                    
                    // Instructions
                    Text("Type the characters as they appear")
                        .foregroundColor(.gray)
                        .font(.system(size: 16))
                        .padding(.bottom, 50)
                }
            }
        }
        .focusable()
        .onKeyPress { keyPress in
            if let character = keyPress.characters.first {
                typingMill.processKeyPress(character)
                typingMill.updateScrolling()
            }
            return .handled
        }
    }
}

#Preview {
    ContentView()
}
