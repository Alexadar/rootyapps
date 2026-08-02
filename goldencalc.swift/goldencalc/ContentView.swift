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

    var body: some View {
        Group {
            #if os(macOS)
            MacOSContentView(
                model: model,
                valueA: $valueA,
                valueB: $valueB,
                valueC: $valueC,
                isApplyingModelUpdate: $isApplyingModelUpdate,
                coefA: coefA,
                coefB: coefB,
                ratio: ratio,
                calculateFromA: calculateFromA,
                calculateFromB: calculateFromB,
                calculateFromC: calculateFromC,
                resetValues: resetValues
            )
            #elseif os(watchOS)
            WatchOSContentView(
                model: model,
                valueA: $valueA,
                valueB: $valueB,
                valueC: $valueC,
                isApplyingModelUpdate: $isApplyingModelUpdate,
                coefA: coefA,
                coefB: coefB,
                ratio: ratio,
                calculateFromA: calculateFromA,
                calculateFromB: calculateFromB,
                calculateFromC: calculateFromC,
                resetValues: resetValues
            )
            #elseif os(tvOS)
            TVOSContentView(
                model: model,
                valueA: $valueA,
                valueB: $valueB,
                valueC: $valueC,
                isApplyingModelUpdate: $isApplyingModelUpdate,
                coefA: coefA,
                coefB: coefB,
                ratio: ratio,
                calculateFromA: calculateFromA,
                calculateFromB: calculateFromB,
                calculateFromC: calculateFromC,
                resetValues: resetValues
            )
            #else
            IOSContentView(
                model: model,
                valueA: $valueA,
                valueB: $valueB,
                valueC: $valueC,
                isApplyingModelUpdate: $isApplyingModelUpdate,
                coefA: coefA,
                coefB: coefB,
                ratio: ratio,
                calculateFromA: calculateFromA,
                calculateFromB: calculateFromB,
                calculateFromC: calculateFromC,
                resetValues: resetValues
            )
            #endif
        }
    }

    // MARK: - Calculation Methods

    private func calculateFromA() {
        if isApplyingModelUpdate { return }
        let filtered = valueA.filter { $0.isNumber || $0 == "." || $0 == "-" }
        guard let a = Float(filtered) else {
            isApplyingModelUpdate = true
            valueB = ""
            valueC = ""
            DispatchQueue.main.async {
                self.isApplyingModelUpdate = false
            }
            return
        }

        isApplyingModelUpdate = true
        let (b, c) = model.calcFromA(a)
        valueB = formatNumber(Double(b))
        valueC = formatNumber(Double(c))
        DispatchQueue.main.async {
            self.isApplyingModelUpdate = false
        }
    }

    private func calculateFromB() {
        if isApplyingModelUpdate { return }
        let filtered = valueB.filter { $0.isNumber || $0 == "." || $0 == "-" }
        guard let b = Float(filtered) else {
            isApplyingModelUpdate = true
            valueA = ""
            valueC = ""
            DispatchQueue.main.async {
                self.isApplyingModelUpdate = false
            }
            return
        }

        isApplyingModelUpdate = true
        let (a, c) = model.calcFromB(b)
        valueA = formatNumber(Double(a))
        valueC = formatNumber(Double(c))
        DispatchQueue.main.async {
            self.isApplyingModelUpdate = false
        }
    }

    private func calculateFromC() {
        if isApplyingModelUpdate { return }
        let filtered = valueC.filter { $0.isNumber || $0 == "." || $0 == "-" }
        guard let c = Float(filtered) else {
            isApplyingModelUpdate = true
            valueA = ""
            valueB = ""
            DispatchQueue.main.async {
                self.isApplyingModelUpdate = false
            }
            return
        }

        isApplyingModelUpdate = true
        let (a, b) = model.calcFromC(c)
        valueA = formatNumber(Double(a))
        valueB = formatNumber(Double(b))
        DispatchQueue.main.async {
            self.isApplyingModelUpdate = false
        }
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

// MARK: - Helper Views

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
        #elseif os(iOS)
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
        #elseif os(iOS)
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
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
}

#Preview {
    ContentView()
}
