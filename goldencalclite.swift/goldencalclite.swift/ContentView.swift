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
        NavigationView {
            VStack(spacing: 20) {
                // Header section
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "function")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("Golden ratio values")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                        Button("Reset") {
                            resetCalculation()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal)
                }
                
                // Main card content
                VStack(spacing: 30) {
                    // Input section
                    VStack(spacing: 15) {
                        Text("Whole is:")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        TextField("Enter value", text: $inputValue)
                            .textFieldStyle(.roundedBorder)
                            .font(.title)
                            .multilineTextAlignment(.center)
                            .onChange(of: inputValue) { _, newValue in
                                calculateRatios(from: newValue)
                            }
                    }
                    
                    // Results section
                    VStack(spacing: 15) {
                        Text("Ratios are:")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("\(partA) and \(partB)")
                            .font(.title)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(NSColor.quaternaryLabelColor))
                            )
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(color: .gray.opacity(0.2), radius: 5, x: 0, y: 2)
                )
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Golden Ratio")
            .background(Color(NSColor.windowBackgroundColor))
        }
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
