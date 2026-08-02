import SwiftUI

struct SummarizeProgressView: View {
    @EnvironmentObject var summarizerState: SummarizerStateManager
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Main content card
            VStack(spacing: 30) {
                Spacer()

                VStack(spacing: 20) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)

                    Text("Processing...")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text("AI is analyzing and summarizing your content")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                VStack(spacing: 15) {
                    ProgressView(value: summarizerState.progress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .scaleEffect(x: 1, y: 3, anchor: .center)

                    Text("\(Int(summarizerState.progress * 100))%")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 40)

                Spacer()

                Button(action: {
                    summarizerState.cancelSummarization()
                    isPresented = false
                }) {
                    Text("Cancel")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red)
                        .cornerRadius(10)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            }
            .frame(maxWidth: 400, maxHeight: 500)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    #if os(macOS)
                    .fill(Color(NSColor.windowBackgroundColor))
                    #else
                    .fill(Color(UIColor.systemBackground))
                    #endif
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .padding(40)
        }
        .onChange(of: summarizerState.state) { state in
            if state == .completed {
                // Don't dismiss here - let the parent view handle navigation
                // isPresented = false
            } else if state == .error || state == .idle {
                isPresented = false
            }
        }
    }
}

#Preview("Progress - Starting") {
    @Previewable @StateObject var summarizerState = {
        let manager = SummarizerStateManager()
        manager.state = .progress
        manager.progress = 0.0
        return manager
    }()

    SummarizeProgressView(isPresented: .constant(true))
        .environmentObject(summarizerState)
        .environmentObject(NavigationCoordinator())
}

#Preview("Progress - Mid Progress") {
    @Previewable @StateObject var summarizerState = {
        let manager = SummarizerStateManager()
        manager.state = .progress
        manager.progress = 0.45
        return manager
    }()

    SummarizeProgressView(isPresented: .constant(true))
        .environmentObject(summarizerState)
        .environmentObject(NavigationCoordinator())
}

#Preview("Progress - Almost Complete") {
    @Previewable @StateObject var summarizerState = {
        let manager = SummarizerStateManager()
        manager.state = .progress
        manager.progress = 0.87
        return manager
    }()

    SummarizeProgressView(isPresented: .constant(true))
        .environmentObject(summarizerState)
        .environmentObject(NavigationCoordinator())
}
