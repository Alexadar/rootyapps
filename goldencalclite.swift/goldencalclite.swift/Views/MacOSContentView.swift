//
//  MacOSContentView.swift
//  goldencalclite.swift
//
//  Platform-specific view for macOS with liquid glass design
//

import SwiftUI

#if os(macOS)
import AppKit

struct MacOSContentView: View {
    @Binding var inputValue: String
    @Binding var partA: String
    @Binding var partB: String

    let coefA: Double
    let coefB: Double
    let ratio: Double

    let calculateRatios: (String) -> Void
    let resetCalculation: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerView

                // Calculator Card
                calculatorCard

                // Usage Card
                usageCard
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 430, idealWidth: 430, maxWidth: .infinity,
               minHeight: 700, idealHeight: 700, maxHeight: .infinity)
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Golden Ratio Calculator Lite")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Calculate parts from whole")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.bottom, 10)
    }

    private var calculatorCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "calculator")
                    .foregroundColor(.blue)
                Text("Golden ratio values")
                    .font(.headline)
                Spacer()
                Button("Reset") {
                    resetCalculation()
                }
                .foregroundColor(.blue)
            }

            Divider()

            // Input section
            VStack(spacing: 15) {
                Text("Whole is:")
                    .font(.title2)
                    .fontWeight(.medium)

                TextField("Enter value", text: $inputValue)
                    .font(.system(size: 48, weight: .regular, design: .default))
                    .multilineTextAlignment(.center)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.vertical, 10)
                    .onChange(of: inputValue) { _, newValue in
                        calculateRatios(newValue)
                    }
            }

            Divider()

            // Results section
            VStack(spacing: 15) {
                Text("Ratios are:")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("\(partA) and \(partB)")
                    .font(.system(size: 48, weight: .regular, design: .default))
                    .foregroundColor(.primary)
            }
        }
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
                Text("Enter the whole value to calculate golden ratio parts")
                    .font(.subheadline)

                Text("Parts are calculated using:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.top, 8)

                Text("• Greater part = whole × \(String(format: "%.10f", coefA))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("• Lesser part = whole × \(String(format: "%.10f", coefB))")
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

#Preview("Golden Ratio Lite - macOS") {
    @Previewable @State var inputValue = "100"
    @Previewable @State var partA = "61.80"
    @Previewable @State var partB = "38.20"

    MacOSContentView(
        inputValue: $inputValue,
        partA: $partA,
        partB: $partB,
        coefA: 0.6180339887,
        coefB: 0.3819660113,
        ratio: 1.6180339887,
        calculateRatios: { _ in },
        resetCalculation: {}
    )
    .frame(width: 430, height: 700)
}

#endif
