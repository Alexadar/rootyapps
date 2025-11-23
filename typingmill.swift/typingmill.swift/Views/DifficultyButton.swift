//
//  DifficultyButton.swift
//  typingmill.swift
//
//  Created by Oleksandr Koreniuk on 20.09.2025.
//

import SwiftUI

struct DifficultyButton: View {
    let difficulty: Int
    let isPressed: Bool
    var size: CGFloat = 50
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(difficulty)")
                .font(.system(size: size * 0.36, weight: .medium))
                .foregroundColor(isPressed ? .black : .white)
                .frame(width: size, height: size)
                .background(isPressed ? .white : .black)
                .border(.white, width: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    HStack {
        DifficultyButton(difficulty: 1, isPressed: true) { }
        DifficultyButton(difficulty: 2, isPressed: false) { }
        DifficultyButton(difficulty: 3, isPressed: false) { }
        DifficultyButton(difficulty: 4, isPressed: false) { }
    }
    .background(.black)
}
