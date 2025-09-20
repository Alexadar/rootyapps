//
//  MillElementView.swift
//  typingmill.swift
//
//  Created by Oleksandr Koreniuk on 20.09.2025.
//

import SwiftUI

struct MillElementView: View {
    @ObservedObject var element: MillElement
    
    var body: some View {
        HStack(spacing: 0) {
            if element.type == .word {
                // Completed text (white)
                Text(element.doneText)
                    .foregroundColor(.white)
                    .font(.system(size: 24, design: .monospaced))
                
                // Current character (underlined white)
                if !element.notDoneText.isEmpty && element.isCurrent {
                    Text(String(element.notDoneText.first!))
                        .foregroundColor(.white)
                        .font(.system(size: 24, design: .monospaced))
                        .underline()
                    
                    // Remaining text (gray)
                    if element.notDoneText.count > 1 {
                        Text(String(element.notDoneText.dropFirst()))
                            .foregroundColor(.gray)
                            .font(.system(size: 24, design: .monospaced))
                    }
                } else {
                    // Remaining text (gray)
                    Text(element.notDoneText)
                        .foregroundColor(.gray)
                        .font(.system(size: 24, design: .monospaced))
                }
            } else {
                // Space element
                Text(element.isCurrent ? "_" : " ")
                    .foregroundColor(.white)
                    .font(.system(size: 24, design: .monospaced))
                    .frame(width: 20)
            }
        }
        .opacity(element.isFadedOut ? 0 : 1)
        .animation(.easeInOut(duration: 0.3), value: element.isFadedOut)
    }
}

#Preview {
    VStack {
        MillElementView(element: MillElement(type: .word, text: "hello"))
        MillElementView(element: MillElement(type: .space))
    }
    .background(.black)
}
