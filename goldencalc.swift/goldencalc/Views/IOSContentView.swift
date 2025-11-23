//
//  IOSContentView.swift
//  goldencalc
//
//  Platform-specific view for iOS/iPadOS
//

import SwiftUI

#if os(iOS)
struct IOSContentView: View {
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
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Calculator Card
                    calculatorCard

                    // Constants Card
                    constantsCard

                    // Math Card
                    mathCard

                    // Usage Card
                    usageCard
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Golden Ratio")
            .navigationBarTitleDisplayMode(.large)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }

    private var calculatorCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "calculator")
                    .foregroundColor(.blue)
                Text("Golden ratio calculator")
                    .font(.headline)
                Spacer()
                Button("Reset") {
                    resetValues()
                }
                .foregroundColor(.blue)
            }

            // Input fields
            VStack(spacing: 15) {
                inputField(label: "a =", value: $valueA, field: .a, calculate: calculateFromA)
                inputField(label: "b =", value: $valueB, field: .b, calculate: calculateFromB)
                inputField(label: "c =", value: $valueC, field: .c, calculate: calculateFromC)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func inputField(label: String, value: Binding<String>, field: Field, calculate: @escaping () -> Void) -> some View {
        HStack {
            Text(label)
                .frame(width: 30, alignment: .leading)
            TextField("Enter value", text: value)
                .focused($focusedField, equals: field)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onChange(of: value.wrappedValue) { newValue in
                    if isApplyingModelUpdate { return }
                    let filtered = newValue.filter { $0.isNumber || $0 == "." || $0 == "-" }
                    if filtered != newValue {
                        value.wrappedValue = filtered
                        return
                    }
                    calculate()
                }
            CopyPasteButtons(value: value, onPaste: {
                DispatchQueue.main.async {
                    if isApplyingModelUpdate { return }
                    let filtered = value.wrappedValue.filter { $0.isNumber || $0 == "." || $0 == "-" }
                    value.wrappedValue = filtered
                    calculate()
                }
            })
        }
    }

    private var constantsCard: some View {
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
    }

    private var mathCard: some View {
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
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private var usageCard: some View {
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
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}
#endif
