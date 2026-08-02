import SwiftUI

struct ResultView: View {
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var summarizerState: SummarizerStateManager
    @State private var showingCopyAlert = false
    
    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                Text(summarizerState.result)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    .textSelection(.enabled)
            }
            
            VStack(spacing: 10) {
                Button(action: {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summarizerState.result, forType: .string)
                    #else
                    UIPasteboard.general.string = summarizerState.result
                    #endif
                    showingCopyAlert = true
                }) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                            .font(.title2)
                            .foregroundColor(.white)
                        Text("Copy to clipboard")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                
                Button(action: {
                    navigationCoordinator.navigateToRoot()
                }) {
                    Text("Return to start page")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                }
            }
        }
        .padding()
        .navigationTitle("Result")
        .alert("Copied!", isPresented: $showingCopyAlert) {
            Button("OK") { }
        } message: {
            Text("The summary has been copied to your clipboard.")
        }
    }
}

#Preview("Result - Short Summary") {
    @Previewable @StateObject var summarizerState = {
        let manager = SummarizerStateManager()
        manager.result = "This is a sample summary of the text that was processed by the AI model. It contains the key points and main ideas from the original content."
        manager.state = .completed
        return manager
    }()

    NavigationView {
        ResultView()
            .environmentObject(NavigationCoordinator())
            .environmentObject(summarizerState)
    }
}

#Preview("Result - Long Summary") {
    @Previewable @StateObject var summarizerState = {
        let manager = SummarizerStateManager()
        manager.result = """
        This is a comprehensive summary of a longer document that was processed by the AI model.

        Key Points:
        • The document discusses multiple important topics
        • Each topic is analyzed in detail with supporting evidence
        • The summary maintains the core message while reducing length

        Main Findings:
        The analysis reveals several interesting insights about the subject matter. These findings are based on careful examination of the source material and represent the most significant conclusions.

        Conclusion:
        Overall, the document provides valuable information that has been successfully condensed while preserving the essential meaning and context.
        """
        manager.state = .completed
        return manager
    }()

    NavigationView {
        ResultView()
            .environmentObject(NavigationCoordinator())
            .environmentObject(summarizerState)
    }
}
