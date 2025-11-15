//
//  IOSContentView.swift
//  goldencalclite.swift
//
//  Platform-specific view for iOS
//

import SwiftUI

#if !os(macOS)
struct IOSContentView: View {
    @Binding var inputValue: String
    @Binding var partA: String
    @Binding var partB: String

    let calculateRatios: (String) -> Void
    let resetCalculation: () -> Void

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

                TextField("Enter value", text: $inputValue)
                    .font(.system(size: 48))
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .onChange(of: inputValue) { _, newValue in
                        calculateRatios(newValue)
                    }
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
}
#endif
