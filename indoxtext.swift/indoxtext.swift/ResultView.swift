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
                    NSPasteboard.general.setString(summarizerState.result, forType: .string)
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

#Preview {
    NavigationView {
        ResultView()
            .environmentObject(NavigationCoordinator())
            .environmentObject({
                let manager = SummarizerStateManager()
                manager.result = "This is a sample summary of the text that was processed by the AI model. It contains the key points and main ideas from the original content."
                return manager
            }())
    }
}
