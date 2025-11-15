//
//  WatchOSContentView.swift
//  goldencalc
//
//  Platform-specific view for watchOS
//

import SwiftUI

#if os(watchOS)
struct WatchOSContentView: View {
    @ObservedObject var model: GoldenRatioModel
    @Binding var valueA: String
    @Binding var valueB: String
    @Binding var valueC: String
    @Binding var isApplyingModelUpdate: Bool

    let coefA: Double
    let coefB: Double
    let ratio: Double

    let calculateFromA: () -> Void
    let calculateFromB: () -> Void
    let calculateFromC: () -> Void
    let resetValues: () -> Void

    var body: some View {
        TabView {
            // Calculator Tab
            ScrollView {
                VStack(spacing: 12) {
                    Text("Golden ratio calculator")
                        .font(.headline)

                    inputField(label: "a:", value: $valueA, calculate: calculateFromA)
                    inputField(label: "b:", value: $valueB, calculate: calculateFromB)
                    inputField(label: "c:", value: $valueC, calculate: calculateFromC)

                    Button("Reset") {
                        resetValues()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(8)
            }
            .navigationTitle("Golden Ratio")

            // Constants Tab
            ScrollView {
                VStack(spacing: 10) {
                    Text("Constants")
                        .font(.headline)

                    constantRow(value: String(format: "%.8f", coefA))
                    constantRow(value: String(format: "%.8f", coefB))
                    constantRow(value: String(format: "%.8f", ratio))
                }
                .padding(8)
            }

            // Math Info Tab
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Math")
                        .font(.headline)

                    Text("Formulas used")
                        .font(.caption)
                        .fontWeight(.medium)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("a * \(String(format: "%.4f", coefA)) + b * \(String(format: "%.4f", coefB)) = c")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Text("c * (1-1 / \(String(format: "%.4f", ratio))) = b")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Text("c / \(String(format: "%.4f", ratio)) = a")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
            }

            // Usage Info Tab
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Usage")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Put value in any field to calculate parts and whole")
                            .font(.caption)

                        Text("Swipe between tabs to view constants and formulas")
                            .font(.caption)
                    }
                }
                .padding(8)
            }
        }
        .tabViewStyle(.page)
    }

    private func inputField(label: String, value: Binding<String>, calculate: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .leading)

            TextField("0.0", text: value)
                .textFieldStyle(.plain)
                .onChange(of: value.wrappedValue) { oldValue, newValue in
                    if isApplyingModelUpdate { return }
                    let filtered = newValue.filter { $0.isNumber || $0 == "." || $0 == "-" }
                    if filtered != newValue {
                        value.wrappedValue = filtered
                        return
                    }
                    calculate()
                }
        }
        .padding(.vertical, 4)
    }

    private func constantRow(value: String) -> some View {
        Text(value)
            .font(.system(.caption, design: .monospaced))
    }
}
#endif
