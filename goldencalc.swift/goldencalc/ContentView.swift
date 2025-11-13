//
//  ContentView.swift
//  goldencalc
//
//  Created by Oleksandr Koreniuk on 19.09.2025.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    // Golden ratio constants
    private let coefA = 0.6180339887
    private let coefB = 0.3819660113
    private let ratio = 1.6180339887
    
    @StateObject private var model = GoldenRatioModel()
    @State private var isApplyingModelUpdate: Bool = false
    @State private var valueA: String = ""
    @State private var valueB: String = ""
    @State private var valueC: String = ""
    
    private enum Field {
        case a, b, c
    }
    @FocusState private var focusedField: Field?

    var body: some View {
        Group {
            #if os(macOS)
            NavigationStack {
                contentView
            }
            #else
            NavigationView {
                contentView
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 430, idealWidth: 430, maxWidth: .infinity,
               minHeight: 932, idealHeight: 932, maxHeight: .infinity)
        #endif
    }

    private var contentView: some View {
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
                            HStack {
                                Text("a =")
                                    .frame(width: 30, alignment: .leading)
                                TextField("Enter value", text: $valueA)
                                    .focused($focusedField, equals: .a)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onChange(of: valueA) { newValue in
                                        if isApplyingModelUpdate { return }

                                        // allow digits, decimal point and minus sign
                                        let filtered = newValue.filter { $0.isNumber || $0 == "." || $0 == "-" }
                                        if filtered != newValue {
                                            valueA = filtered
                                            return
                                        }

                                        // Delegate calculation to centralized function which respects focusedField
                                        calculateFromA()
                                    }
                                CopyPasteButtons(value: $valueA, onPaste: {
                                    // Paste sets the bound value; trigger same handling async to let TextField update
                                    DispatchQueue.main.async {
                                        if isApplyingModelUpdate { return }
                                        let filtered = valueA.filter { $0.isNumber || $0 == "." || $0 == "-" }
                                        valueA = filtered
                                        calculateFromA()
                                    }
                                })
                            }

                            HStack {
                                Text("b =")
                                    .frame(width: 30, alignment: .leading)
                                TextField("Enter value", text: $valueB)
                                    .focused($focusedField, equals: .b)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onChange(of: valueB) { newValue in
                                        if isApplyingModelUpdate { return }

                                        // allow digits, decimal point and minus sign
                                        let filtered = newValue.filter { $0.isNumber || $0 == "." || $0 == "-" }
                                        if filtered != newValue {
                                            valueB = filtered
                                            return
                                        }

                                        // Delegate calculation to centralized function which respects focusedField
                                        calculateFromB()
                                    }
                                CopyPasteButtons(value: $valueB, onPaste: {
                                    DispatchQueue.main.async {
                                        if isApplyingModelUpdate { return }
                                        let filtered = valueB.filter { $0.isNumber || $0 == "." || $0 == "-" }
                                        valueB = filtered
                                        calculateFromB()
                                    }
                                })
                            }

                            HStack {
                                Text("c =")
                                    .frame(width: 30, alignment: .leading)
                                TextField("Enter value", text: $valueC)
                                    .focused($focusedField, equals: .c)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onChange(of: valueC) { newValue in
                                        if isApplyingModelUpdate { return }

                                        // allow digits, decimal point and minus sign
                                        let filtered = newValue.filter { $0.isNumber || $0 == "." || $0 == "-" }
                                        if filtered != newValue {
                                            valueC = filtered
                                            return
                                        }

                                        // Delegate calculation to centralized function which respects focusedField
                                        calculateFromC()
                                    }
                                CopyPasteButtons(value: $valueC, onPaste: {
                                    DispatchQueue.main.async {
                                        if isApplyingModelUpdate { return }
                                        let filtered = valueC.filter { $0.isNumber || $0 == "." || $0 == "-" }
                                        valueC = filtered
                                        calculateFromC()
                                    }
                                })
                            }
                        }
                    }
                    .padding()
                    #if os(macOS)
                    .background(Color(NSColor.controlBackgroundColor))
                    #else
                    .background(Color(.systemGray6))
                    #endif
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
                    #if os(macOS)
                    .background(Color(NSColor.controlBackgroundColor))
                    #else
                    .background(Color(.systemGray6))
                    #endif
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    #if os(macOS)
                    .background(Color(NSColor.controlBackgroundColor))
                    #else
                    .background(Color(.systemGray6))
                    #endif
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    #if os(macOS)
                    .background(Color(NSColor.controlBackgroundColor))
                    #else
                    .background(Color(.systemGray6))
                    #endif
                    .cornerRadius(10)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Golden Ratio")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
    
    // MARK: - Calculation Methods

    // Updated calculation: use GoldenRatioModel and a suppression flag to avoid cascade updates.
    // Avoid writing back to the currently focused input to prevent cascade/update-of-source-field.
    private func calculateFromA() {
        if isApplyingModelUpdate { return }
        let filtered = valueA.filter { $0.isNumber || $0 == "." || $0 == "-" }
        // do not reassign source field here to avoid moving cursor while user types
        guard let a = Float(filtered) else {
            isApplyingModelUpdate = true
            if focusedField != .b { valueB = "" }
            if focusedField != .c { valueC = "" }
            isApplyingModelUpdate = false
            return
        }

        isApplyingModelUpdate = true
        let (b, c) = model.calcFromA(a)
        if focusedField != .b { valueB = formatNumber(Double(b)) }
        if focusedField != .c { valueC = formatNumber(Double(c)) }
        isApplyingModelUpdate = false
    }

    private func calculateFromB() {
        if isApplyingModelUpdate { return }
        let filtered = valueB.filter { $0.isNumber || $0 == "." || $0 == "-" }
        // do not reassign source field here to avoid moving cursor while user types
        guard let b = Float(filtered) else {
            isApplyingModelUpdate = true
            if focusedField != .a { valueA = "" }
            if focusedField != .c { valueC = "" }
            isApplyingModelUpdate = false
            return
        }

        isApplyingModelUpdate = true
        let (a, c) = model.calcFromB(b)
        if focusedField != .a { valueA = formatNumber(Double(a)) }
        if focusedField != .c { valueC = formatNumber(Double(c)) }
        isApplyingModelUpdate = false
    }

    private func calculateFromC() {
        if isApplyingModelUpdate { return }
        let filtered = valueC.filter { $0.isNumber || $0 == "." || $0 == "-" }
        // do not reassign source field here to avoid moving cursor while user types
        guard let c = Float(filtered) else {
            isApplyingModelUpdate = true
            if focusedField != .a { valueA = "" }
            if focusedField != .b { valueB = "" }
            isApplyingModelUpdate = false
            return
        }

        isApplyingModelUpdate = true
        let (a, b) = model.calcFromC(c)
        if focusedField != .a { valueA = formatNumber(Double(a)) }
        if focusedField != .b { valueB = formatNumber(Double(b)) }
        isApplyingModelUpdate = false
    }

    private func resetValues() {
        valueA = ""
        valueB = ""
        valueC = ""
    }

    private func formatNumber(_ number: Double) -> String {
        return String(format: "%.10g", number)
    }
}

struct CopyPasteButtons: View {
    @Binding var value: String
    let onPaste: () -> Void

    var body: some View {
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

    private func pasteFromClipboard() {
        #if os(macOS)
        if let clipboardString = NSPasteboard.general.string(forType: .string) {
            let filtered = clipboardString.filter { $0.isNumber || $0 == "." || $0 == "-" }
            value = filtered
            onPaste()
        }
        #else
        if let clipboardString = UIPasteboard.general.string {
            let filtered = clipboardString.filter { $0.isNumber || $0 == "." || $0 == "-" }
            value = filtered
            onPaste()
        }
        #endif
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
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
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

#Preview {
    ContentView()
}
