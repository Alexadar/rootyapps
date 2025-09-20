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
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(typingMill.millElements) { element in
                                    MillElementView(element: element)
                                        .id(element.id)
                                }
                            }
                            .padding(.horizontal, geometry.size.width / 2)
                        }
                        .frame(height: 100)
                        .clipped()
                        .onChange(of: typingMill.currentElementIndex) { _, newIndex in
                            // Add bounds checking to prevent crashes
                            guard newIndex >= 0 && newIndex < typingMill.millElements.count else { return }
                            let currentElement = typingMill.millElements[newIndex]
                            withAnimation(.linear(duration: 0.1)) {
                                proxy.scrollTo(currentElement.id, anchor: .center)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // QWERTY Keyboard
                    QwertyKeyboardView(
                        currentChar: typingMill.currentCharacter
                    ) { character in
                        typingMill.processKeyPress(character)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    
                    // Instructions
                    Text("Type the characters as they appear or use the keyboard below")
                        .foregroundColor(.gray)
                        .font(.system(size: 16))
                        .padding(.bottom, 30)
                }
            }
        }
        .focusable()
        .onKeyPress { keyPress in
            if let character = keyPress.characters.first {
                typingMill.processKeyPress(character)
            }
            return .handled
        }
    }
}

#Preview {
    ContentView()
}
