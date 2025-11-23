//
//  IOSContentView.swift
//  typingmill.swift
//
//  Created by Oleksandr Koreniuk on 20.09.2025.
//

#if os(iOS)
import SwiftUI
import UIKit

struct IOSContentView: View {
    @StateObject private var typingMill = TypingMill()
    @State private var isAnimationEnabled: Bool = true
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }

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

                // Hidden TextField to capture keyboard input
                TextField("", text: .constant(""))
                    .focused($isTextFieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .opacity(0)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)

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
                                .font(.system(size: isIPad ? 20 : 16))
                                .frame(width: isIPad ? 44 : 36, height: isIPad ? 44 : 36)
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
                    .padding(.horizontal, isIPad ? 24 : 16)
                    .padding(.top, isIPad ? 20 : 12)

                    // Main typing area - aligned to top
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(typingMill.millElements) { element in
                                    MillElementView(element: element, fontSize: isIPad ? 32 : 22)
                                        .id(element.id)
                                }
                            }
                            .padding(.horizontal, geometry.size.width / 2)
                        }
                        .frame(height: isIPad ? 120 : 80)
                        .clipped()
                        .onChange(of: typingMill.currentElementIndex) { _, newIndex in
                            DispatchQueue.main.async {
                                guard newIndex >= 0 && newIndex < typingMill.millElements.count else { return }
                                let currentElement = typingMill.millElements[newIndex]
                                withAnimation(.linear(duration: 0.1)) {
                                    proxy.scrollTo(currentElement.id, anchor: .center)
                                }
                            }
                        }
                    }
                    .padding(.top, isIPad ? 40 : 20)

                    Spacer()

                    // Difficulty controls
                    HStack(spacing: isIPad ? 24 : 12) {
                        Text("Difficulty")
                            .foregroundColor(.white)
                            .font(.system(size: isIPad ? 28 : 18, weight: .regular, design: .monospaced))
                            .kerning(isIPad ? 4 : 2)
                        ForEach(1...4, id: \.self) { difficulty in
                            DifficultyButton(
                                difficulty: difficulty,
                                isPressed: typingMill.currentDifficulty == difficulty,
                                size: isIPad ? 50 : 40
                            ) {
                                DispatchQueue.main.async {
                                    typingMill.changeDifficulty(difficulty)
                                }
                            }
                        }
                    }
                    .padding(.bottom, isIPad ? 30 : 20)
                }
            }
            .onTapGesture {
                isTextFieldFocused = true
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification)) { notification in
            if let textField = notification.object as? UITextField,
               let text = textField.text,
               let lastChar = text.last {
                DispatchQueue.main.async {
                    // Convert to lowercase for case-insensitive input
                    let lowercaseChar = Character(lastChar.lowercased())
                    typingMill.processKeyPress(lowercaseChar)
                    textField.text = ""
                }
            }
        }
    }
}

// MARK: - iOS-optimized Keyboard View
struct IOSQwertyKeyboardView: View {
    let currentChar: Character?
    let isIPad: Bool
    let onKeyPress: (Character) -> Void

    private let keyboardRows: [[String]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"]
    ]

    private var keySize: CGFloat {
        isIPad ? 50 : 32
    }

    private var keySpacing: CGFloat {
        isIPad ? 8 : 4
    }

    private var fontSize: CGFloat {
        isIPad ? 18 : 14
    }

    var body: some View {
        VStack(spacing: keySpacing) {
            // Top row
            HStack(spacing: keySpacing) {
                ForEach(keyboardRows[0], id: \.self) { key in
                    let lowerCurrent = currentChar.map { String($0).lowercased() }
                    IOSKeyButton(
                        key: key,
                        isHighlighted: lowerCurrent == key.lowercased(),
                        size: keySize,
                        fontSize: fontSize,
                        onPress: { onKeyPress(Character(key.lowercased())) }
                    )
                }
            }

            // Middle row
            HStack(spacing: keySpacing) {
                ForEach(keyboardRows[1], id: \.self) { key in
                    let lowerCurrent = currentChar.map { String($0).lowercased() }
                    IOSKeyButton(
                        key: key,
                        isHighlighted: lowerCurrent == key.lowercased(),
                        size: keySize,
                        fontSize: fontSize,
                        onPress: { onKeyPress(Character(key.lowercased())) }
                    )
                }
            }

            // Bottom row
            HStack(spacing: keySpacing) {
                ForEach(keyboardRows[2], id: \.self) { key in
                    let lowerCurrent = currentChar.map { String($0).lowercased() }
                    IOSKeyButton(
                        key: key,
                        isHighlighted: lowerCurrent == key.lowercased(),
                        size: keySize,
                        fontSize: fontSize,
                        onPress: { onKeyPress(Character(key.lowercased())) }
                    )
                }
            }

            // Space bar
            HStack {
                IOSKeyButton(
                    key: "SPACE",
                    isHighlighted: currentChar == " ",
                    size: keySize,
                    fontSize: fontSize - 2,
                    onPress: { onKeyPress(" ") },
                    isSpaceBar: true,
                    spaceBarWidth: isIPad ? 280 : 180
                )
            }
        }
        .padding(isIPad ? 16 : 10)
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
    }
}

struct IOSKeyButton: View {
    let key: String
    let isHighlighted: Bool
    let size: CGFloat
    let fontSize: CGFloat
    let onPress: () -> Void
    var isSpaceBar: Bool = false
    var spaceBarWidth: CGFloat = 180

    var body: some View {
        Button(action: onPress) {
            Text(key)
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundColor(isHighlighted ? .black : .white)
                .frame(
                    width: isSpaceBar ? spaceBarWidth : size,
                    height: size
                )
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHighlighted ? Color.white : Color.gray.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isHighlighted ? Color.white : Color.gray.opacity(0.5), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isHighlighted ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isHighlighted)
    }
}

#Preview("iPhone") {
    IOSContentView()
}

#Preview("iPad") {
    IOSContentView()
        .previewDevice(PreviewDevice(rawValue: "iPad Pro (12.9-inch)"))
}
#endif
