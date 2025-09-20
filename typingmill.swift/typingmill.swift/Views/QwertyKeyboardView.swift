//
//  QwertyKeyboardView.swift
//  typingmill.swift
//
//  Created by Oleksandr Koreniuk on 20.09.2025.
//

import SwiftUI

struct QwertyKeyboardView: View {
    let currentChar: Character?
    let onKeyPress: (Character) -> Void
    
    // QWERTY keyboard layout
    private let keyboardRows: [[String]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"]
    ]
    
    var body: some View {
        VStack(spacing: 8) {
            // Top row
            HStack(spacing: 6) {
                ForEach(keyboardRows[0], id: \.self) { key in
                    KeyButton(
                        key: key,
                        isHighlighted: shouldHighlight(key),
                        onPress: { onKeyPress(Character(key.lowercased())) }
                    )
                }
            }
            
            // Middle row
            HStack(spacing: 6) {
                ForEach(keyboardRows[1], id: \.self) { key in
                    KeyButton(
                        key: key,
                        isHighlighted: shouldHighlight(key),
                        onPress: { onKeyPress(Character(key.lowercased())) }
                    )
                }
            }
            
            // Bottom row
            HStack(spacing: 6) {
                ForEach(keyboardRows[2], id: \.self) { key in
                    KeyButton(
                        key: key,
                        isHighlighted: shouldHighlight(key),
                        onPress: { onKeyPress(Character(key.lowercased())) }
                    )
                }
            }
            
            // Space bar
            HStack {
                KeyButton(
                    key: "SPACE",
                    isHighlighted: currentChar == " ",
                    onPress: { onKeyPress(" ") },
                    isSpaceBar: true
                )
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
    }
    
    private func shouldHighlight(_ key: String) -> Bool {
        guard let currentChar = currentChar else { return false }
        return key.lowercased() == String(currentChar).lowercased()
    }
}

struct KeyButton: View {
    let key: String
    let isHighlighted: Bool
    let onPress: () -> Void
    let isSpaceBar: Bool
    
    init(key: String, isHighlighted: Bool, onPress: @escaping () -> Void, isSpaceBar: Bool = false) {
        self.key = key
        self.isHighlighted = isHighlighted
        self.onPress = onPress
        self.isSpaceBar = isSpaceBar
    }
    
    var body: some View {
        Button(action: onPress) {
            Text(key)
                .font(.system(size: isSpaceBar ? 14 : 16, weight: .medium, design: .monospaced))
                .foregroundColor(isHighlighted ? .black : .white)
                .frame(
                    width: isSpaceBar ? 200 : 35,
                    height: 35
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

#Preview {
    QwertyKeyboardView(currentChar: "a") { char in
        print("Pressed: \(char)")
    }
    .background(.black)
}
