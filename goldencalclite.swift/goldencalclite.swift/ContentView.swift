//
//  ContentView.swift
//  goldencalclite.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SwiftUI
import Foundation

struct ContentView: View {
    @State private var inputValue: String = ""
    @State private var partA: String = "0"
    @State private var partB: String = "0"

    // Golden ratio coefficients
    private let coefA: Double = 0.6180339887
    private let coefB: Double = 0.3819660113
    private let ratio: Double = 1.6180339887

    var body: some View {
        VStack(spacing: 20) {
            // Header section
            VStack(spacing: 4) {
                Text("Golden Ratio")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)

                Text("Calculator Lite")
                    .font(.system(size: 17))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 10)

            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(.gray.opacity(0.3))
                .frame(maxWidth: .infinity)

            // Card header with icon and reset button
            HStack(spacing: 12) {
                Image(systemName: "calculator")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)

                Text("Golden ratio values")
                    .font(.system(size: 22))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: resetCalculation) {
                    Text("Reset")
                        .font(.system(size: 17))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)

            Divider()
                .padding(.horizontal)

            // Input section
            VStack(spacing: 20) {
                Text("Whole is:")
                    .font(.system(size: 28))
                    .foregroundColor(.primary)

                #if os(iOS)
                TextField("Enter value", text: $inputValue)
                    .font(.system(size: 48))
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .onChange(of: inputValue) { _, newValue in
                        calculateRatios(from: newValue)
                    }
                #else
                TextField("Enter value", text: $inputValue)
                    .font(.system(size: 48))
                    .multilineTextAlignment(.center)
                    .onChange(of: inputValue) { _, newValue in
                        calculateRatios(from: newValue)
                    }
                #endif
            }
            .padding(.vertical, 20)

            Divider()
                .padding(.horizontal)

            // Results section
            VStack(spacing: 20) {
                Text("Ratios are:")
                    .font(.system(size: 28))
                    .foregroundColor(.primary)

                Text("\(partA) and \(partB)")
                    .font(.system(size: 48))
                    .foregroundColor(.primary)
            }
            .padding(.vertical, 20)
        }
        .padding(.top, 60)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background)
    }
    
    private func calculateRatios(from input: String) {
        guard !input.isEmpty,
              let wholeValue = Double(input),
              wholeValue > 0 else {
            partA = "0"
            partB = "0"
            return
        }
        
        // Calculate the two parts using golden ratio coefficients
        let calculatedA = wholeValue * coefA
        let calculatedB = wholeValue * coefB
        
        // Round to nearest integer and convert to string
        partA = String(Int(calculatedA.rounded()))
        partB = String(Int(calculatedB.rounded()))
    }
    
    private func resetCalculation() {
        inputValue = ""
        partA = "0"
        partB = "0"
    }
}

#Preview {
    ContentView()
}
