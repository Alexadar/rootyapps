//
//  TVOSContentView.swift
//  goldencalc
//
//  Platform-specific view for tvOS
//

import SwiftUI

#if os(tvOS)
struct TVOSContentView: View {
    @ObservedObject var model: GoldenRatioModel
    @Binding var valueA: String
    @Binding var valueB: String
    @Binding var valueC: String
    @Binding var isApplyingModelUpdate: Bool

    let coefA: Double
    let coefB: Double
    let ratio: Double

    private enum Field {
        case a, b, c
    }
    @FocusState private var focusedField: Field?

    let calculateFromA: () -> Void
    let calculateFromB: () -> Void
    let calculateFromC: () -> Void
    let resetValues: () -> Void

    var body: some View {
        TabView {
            // Calculator Tab
            ZStack {
                ScrollView {
                    VStack(spacing: 30) {
                        Text("Golden ratio calculator")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        GeometryReader { geometry in
                            VStack(spacing: 20) {
                                inputField(label: "a =", value: $valueA, field: .a, calculate: calculateFromA, width: geometry.size.width * 0.9)
                                inputField(label: "b =", value: $valueB, field: .b, calculate: calculateFromB, width: geometry.size.width * 0.9)
                                inputField(label: "c =", value: $valueC, field: .c, calculate: calculateFromC, width: geometry.size.width * 0.9)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(height: 250)

                        // Spacer to prevent reset button from overlaying
                        Spacer()
                            .frame(height: 100)
                    }
                    .padding(40)
                }

                // Reset button pinned to bottom
                VStack {
                    Spacer()
                    Button("Reset") {
                        resetValues()
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 40)
                }
            }
            .tabItem {
                Label("Calculator", systemImage: "calculator")
            }

            // Constants Tab
            ScrollView {
                VStack(spacing: 30) {
                    Text("Constants")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    VStack(spacing: 20) {
                        constantRow(label: "Coefficient A", value: String(format: "%.10f", coefA))
                        constantRow(label: "Coefficient B", value: String(format: "%.10f", coefB))
                        constantRow(label: "Golden Ratio", value: String(format: "%.10f", ratio))
                    }
                    .padding(.horizontal, 100)
                }
                .padding(40)
            }
            .tabItem {
                Label("Constants", systemImage: "doc.text")
            }

            // Math Info Tab
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    Text("Math")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    VStack(alignment: .leading, spacing: 15) {
                        Text("Formulas used")
                            .font(.title2)
                            .fontWeight(.medium)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("a * \(String(format: "%.10f", coefA)) + b * \(String(format: "%.10f", coefB)) = c")
                                .font(.title3)
                                .foregroundColor(.secondary)

                            Text("c * (1-1 / \(String(format: "%.10f", ratio))) = b")
                                .font(.title3)
                                .foregroundColor(.secondary)

                            Text("c / \(String(format: "%.10f", ratio)) = a")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 100)
                }
                .padding(40)
            }
            .tabItem {
                Label("Math", systemImage: "function")
            }

            // Usage Info Tab
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    Text("Usage")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    VStack(alignment: .leading, spacing: 15) {
                        Text("Put value in any field to calculate parts and whole")
                            .font(.title2)

                        Text("Use the remote to navigate between fields and enter values")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 100)
                }
                .padding(40)
            }
            .tabItem {
                Label("Usage", systemImage: "info.circle")
            }
        }
    }

    private func inputField(label: String, value: Binding<String>, field: Field, calculate: @escaping () -> Void, width: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 20) {
                Text(label)
                    .font(.title2)
                    .frame(width: 60, alignment: .leading)

                TextField("Enter value", text: value)
                    .focused($focusedField, equals: field)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .padding(10)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    .onChange(of: value.wrappedValue) { newValue in
                        if isApplyingModelUpdate { return }
                        let filtered = newValue.filter { $0.isNumber || $0 == "." || $0 == "-" }
                        if filtered != newValue {
                            value.wrappedValue = filtered
                            return
                        }
                        calculate()
                    }
                    .onExitCommand {
                        focusedField = nil
                    }
            }
            .frame(width: width)
        }
    }

    private func constantRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.title2)
                .frame(width: 200, alignment: .leading)
            Spacer()
            Text(value)
                .font(.system(.title2, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}
#endif
