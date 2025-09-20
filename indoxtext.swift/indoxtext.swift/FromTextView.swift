import SwiftUI

struct FromTextView: View {
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var summarizerState: SummarizerStateManager
    @State private var showingProgressSheet = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Paste text to summarize")
                .font(.headline)
                .padding(.top)
            
            TextEditor(text: $summarizerState.inputText)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .frame(minHeight: 200)
            
            Button(action: {
                summarizerState.startSummarization()
                showingProgressSheet = true
            }) {
                HStack {
                    Image(systemName: "text.alignleft")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text("Summarize text")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(summarizerState.inputText.isEmpty ? Color.gray : Color.blue)
                .cornerRadius(10)
            }
            .disabled(summarizerState.inputText.isEmpty)
            
            Spacer()
        }
        .padding()
        .navigationTitle("From text")
        .sheet(isPresented: $showingProgressSheet) {
            SummarizeProgressView(isPresented: $showingProgressSheet)
                .environmentObject(summarizerState)
                .environmentObject(navigationCoordinator)
        }
        .onChange(of: summarizerState.state) { state in
            if state == .completed {
                showingProgressSheet = false
                navigationCoordinator.navigate(to: .result)
            }
        }
        .onAppear {
            summarizerState.reset()
        }
    }
}

#Preview {
    NavigationView {
        FromTextView()
            .environmentObject(NavigationCoordinator())
            .environmentObject(SummarizerStateManager())
    }
}
