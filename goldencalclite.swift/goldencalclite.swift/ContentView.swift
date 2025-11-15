//
//  ContentView.swift
//  goldencalclite.swift
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SwiftUI
import Foundation
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @State private var inputValue: String = ""
    @State private var partA: String = "0"
    @State private var partB: String = "0"

    // Golden ratio coefficients
    private let coefA: Double = 0.6180339887
    private let coefB: Double = 0.3819660113
    private let ratio: Double = 1.6180339887

    var body: some View {
        Group {
            #if os(macOS)
            MacOSContentView(
                inputValue: $inputValue,
                partA: $partA,
                partB: $partB,
                coefA: coefA,
                coefB: coefB,
                ratio: ratio,
                calculateRatios: { newValue in calculateRatios(from: newValue) },
                resetCalculation: resetCalculation
            )
            #else
            IOSContentView(
                inputValue: $inputValue,
                partA: $partA,
                partB: $partB,
                calculateRatios: { newValue in calculateRatios(from: newValue) },
                resetCalculation: resetCalculation
            )
            #endif
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
