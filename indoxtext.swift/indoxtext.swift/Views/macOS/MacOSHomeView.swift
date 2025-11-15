//
//  MacOSHomeView.swift
//  indoxtext.swift
//
//  macOS-specific home view with liquid glass design
//

import SwiftUI

#if os(macOS)
struct MacOSHomeView: View {
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator

    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 8) {
                Text("Indox Text")
                    .font(.system(size: 36, weight: .bold))

                Text("AI-powered text summarization")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 40)

            // Action cards
            VStack(spacing: 15) {
                actionCard(
                    title: "Summarize text",
                    icon: "text.alignleft",
                    description: "Paste or type text to summarize",
                    action: { navigationCoordinator.navigate(to: .fromText) }
                )

                actionCard(
                    title: "Summarize file",
                    icon: "doc.text",
                    description: "Select a text or PDF file",
                    action: { navigationCoordinator.navigate(to: .fromFile) }
                )
            }

            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func actionCard(title: String, icon: String, description: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                    .frame(width: 60, height: 60)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview("Indox Home - macOS") {
    MacOSHomeView()
        .environmentObject(NavigationCoordinator())
        .frame(width: 600, height: 500)
}

#endif
