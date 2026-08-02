//
//  MacContentView.swift
//  typingmill.swift
//
//  Created by Oleksandr Koreniuk on 20.09.2025.
//

import SwiftUI

struct MacContentView: View {
    @StateObject private var typingMill = TypingMill()
    @State private var keyMonitor: Any?
    @State private var isAnimationEnabled: Bool = true

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Black background
                Color.black
                    .ignoresSafeArea()

                // Background Animation
                BackgroundAnimationView(
                    isEnabled: isAnimationEnabled,
                    typingChar: typingMill.currentCharacter,
                    typingSpeed: typingMill.typingSpeed,
                    difficulty: typingMill.currentDifficulty,
                    correctKeystroke: typingMill.correctKeystroke
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top controls
                    HStack {
                        Spacer()
                        // Animation toggle button (top-right)
                        Button(action: {
                            isAnimationEnabled.toggle()
                        }) {
                            Image(systemName: isAnimationEnabled ? "eye" : "eye.slash")
                                .foregroundColor(.white)
                                .font(.system(size: 18))
                                .frame(width: 40, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isAnimationEnabled ? Color.blue.opacity(0.3) : Color.gray.opacity(0.3))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isAnimationEnabled ? Color.blue : Color.gray, lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 50)

                    // Main typing area - aligned to top
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
                            // Defer to next runloop to avoid interfering with update cycle
                            DispatchQueue.main.async {
                                // Add bounds checking to prevent crashes
                                guard newIndex >= 0 && newIndex < typingMill.millElements.count else { return }
                                let currentElement = typingMill.millElements[newIndex]
                                withAnimation(.linear(duration: 0.1)) {
                                    proxy.scrollTo(currentElement.id, anchor: .center)
                                }
                            }
                        }
                    }
                    .padding(.top, 40)

                    Spacer()

                    // Difficulty controls (bottom)
                    HStack(spacing: 20) {
                        Text("Difficulty")
                            .foregroundColor(.white)
                            .font(.system(size: 34, weight: .regular, design: .monospaced))
                            .kerning(4)
                        ForEach(1...4, id: \.self) { difficulty in
                            DifficultyButton(
                                difficulty: difficulty,
                                isPressed: typingMill.currentDifficulty == difficulty
                            ) {
                                DispatchQueue.main.async {
                                    typingMill.changeDifficulty(difficulty)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { keyPress in
            if let character = keyPress.characters.first {
                DispatchQueue.main.async {
                    typingMill.processKeyPress(character)
                }
            }
            return .handled
        }
    }
}

#Preview {
    MacContentView()
}
