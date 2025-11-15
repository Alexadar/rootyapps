//
//  MacOSContentView.swift
//  goldencalc
//
//  Platform-specific view for macOS
//

import SwiftUI

#if os(macOS)
import AppKit

struct MacOSContentView: View {
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
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerView

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
        .frame(minWidth: 430, idealWidth: 430, maxWidth: .infinity,
               minHeight: 932, idealHeight: 932, maxHeight: .infinity)
    }

    private var headerView: some View {
        HStack {
            Text("Golden Ratio Tech Calculator")
                .padding(.top, 10)
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer()
        }
        .padding(.bottom, 10)
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
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
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
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
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
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
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
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Transparent Window Classes for Liquid Glass

class TransparentWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        // Add fullSizeContentView to style mask
        var styleMask = style
        styleMask.insert(.fullSizeContentView)

        super.init(contentRect: contentRect, styleMask: styleMask, backing: backingStoreType, defer: flag)

        self.isOpaque = false
        self.backgroundColor = .clear
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden

        // Add single unified visual effect view as background
        let visualEffectView = NSVisualEffectView(frame: contentRect)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.wantsLayer = true

        // Add rounded corners and border for glass effect
        visualEffectView.layer?.cornerRadius = 12
        visualEffectView.layer?.borderWidth = 1
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        visualEffectView.layer?.masksToBounds = true

        // Add subtle shadow for depth
        self.hasShadow = true

        self.contentView = visualEffectView
    }
}

class TransparentWindowController: NSWindowController {
    convenience init<Content: View>(rootView: Content, width: CGFloat, height: CGFloat) {
        let window = TransparentWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.init(window: window)

        // Create hosting view for SwiftUI content
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]

        // Add hosting view to the visual effect view
        if let visualEffectView = window.contentView as? NSVisualEffectView {
            visualEffectView.addSubview(hostingView)
            hostingView.frame = visualEffectView.bounds
        }

        window.center()
    }
}

// MARK: - Preview

#Preview("Golden Ratio Calculator - macOS") {
    @Previewable @State var valueA = "100"
    @Previewable @State var valueB = "61.80"
    @Previewable @State var valueC = "161.80"
    @Previewable @State var isApplyingModelUpdate = false
    @Previewable @StateObject var model = GoldenRatioModel()

    MacOSContentView(
        model: model,
        valueA: $valueA,
        valueB: $valueB,
        valueC: $valueC,
        isApplyingModelUpdate: $isApplyingModelUpdate,
        coefA: 0.6180339887,
        coefB: 0.3819660113,
        ratio: 1.6180339887,
        calculateFromA: {},
        calculateFromB: {},
        calculateFromC: {},
        resetValues: {}
    )
    .frame(width: 430, height: 932)
}

#endif
