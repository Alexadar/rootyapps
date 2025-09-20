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
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("\(difficulty)")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isPressed ? .black : .white)
                .frame(width: 50, height: 50)
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
