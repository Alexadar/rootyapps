//
//  ContentView.swift
//  goldencalc
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SwiftUI

struct ContentView: View {
    // Golden ratio constants
    private let coefA = 0.6180339887
    private let coefB = 0.3819660113
    private let ratio = 1.6180339887
    
    @State private var valueA: String = ""
    @State private var valueB: String = ""
    @State private var valueC: String = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Calculator Card
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Image(systemName: "calculator")
                                .foregroundColor(.blue)
                            Text("Calculator")
                                .font(.headline)
                            Spacer()
                            Button("Reset") {
                                resetValues()
                            }
                            .foregroundColor(.blue)
                        }
                        
                        // Input fields
                        VStack(spacing: 15) {
                            InputRow(label: "a =", value: $valueA, onValueChange: { val in
                                calculateFromA(val)
                            })
                            
                            InputRow(label: "b =", value: $valueB, onValueChange: { val in
                                calculateFromB(val)
                            })
                            
                            InputRow(label: "c =", value: $valueC, onValueChange: { val in
                                calculateFromC(val)
                            })
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    // Constants Card
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.blue)
                            Text("Copy ratio constants to clipboard")
                                .font(.headline)
                        }
                        
                        VStack(spacing: 10) {
                            ConstantRow(value: String(format: "%.10f", coefA))
                            ConstantRow(value: String(format: "%.10f", coefB))
                            ConstantRow(value: String(format: "%.10f", ratio))
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    // Math Card
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)
                            Text("Math")
                                .font(.headline)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Formulas used")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("a * \(String(format: "%.10f", coefA)) + b * \(String(format: "%.10f", coefB)) = c")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("c * (1-1 / \(String(format: "%.10f", ratio))) = b")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("c / \(String(format: "%.10f", ratio)) = a")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    // Usage Card
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Usage")
                                .font(.headline)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Put value in any field to calculate parts and whole")
                                .font(.subheadline)
                            
                            Text("Use copy/paste buttons to copy between devices")
                                .font(.subheadline)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                .padding()
            }
            .navigationTitle("Golden Ratio")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    // MARK: - Calculation Methods
    
    private func calculateFromA(_ value: String) {
        guard let a = Double(value), a != 0 else {
            resetValues()
            valueA = value
            return
        }
        
        let c = a * ratio
        let b = c * coefB
        
        valueA = value
        valueB = formatNumber(b)
        valueC = formatNumber(c)
    }
    
    private func calculateFromB(_ value: String) {
        guard let b = Double(value), b != 0 else {
            resetValues()
            valueB = value
            return
        }
        
        let a = (b / coefB) * coefA
        let c = a * ratio
        
        valueA = formatNumber(a)
        valueB = value
        valueC = formatNumber(c)
    }
    
    private func calculateFromC(_ value: String) {
        guard let c = Double(value), c != 0 else {
            resetValues()
            valueC = value
            return
        }
        
        let a = c * coefA
        let b = c * coefB
        
        valueA = formatNumber(a)
        valueB = formatNumber(b)
        valueC = value
    }
    
    private func resetValues() {
        valueA = ""
        valueB = ""
        valueC = ""
    }
    
    private func formatNumber(_ number: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? ""
    }
}

struct InputRow: View {
    let label: String
    @Binding var value: String
    let onValueChange: (String) -> Void
    
    var body: some View {
        HStack {
            Text(label)
                .frame(width: 30, alignment: .leading)
            
            TextField("Enter value", text: $value)
                .keyboardType(.decimalPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onChange(of: value) { _, newValue in
                    onValueChange(newValue)
                }
            
            Button(action: {
                pasteFromClipboard()
            }) {
                Image(systemName: "clipboard")
                    .foregroundColor(.blue)
            }
            
            Button(action: {
                copyToClipboard(value)
            }) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.blue)
            }
        }
    }
    
    private func pasteFromClipboard() {
        if let clipboardString = UIPasteboard.general.string {
            value = clipboardString
            onValueChange(clipboardString)
        }
    }
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
    }
}

struct ConstantRow: View {
    let value: String
    
    var body: some View {
        HStack {
            Text(value)
                .font(.system(.body, design: .monospaced))
            Spacer()
            Button(action: {
                copyToClipboard(value)
            }) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.blue)
            }
        }
    }
    
    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
    }
}

#Preview {
    ContentView()
}
