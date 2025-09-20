import SwiftUI

struct SummarizeProgressView: View {
    @EnvironmentObject var summarizerState: SummarizerStateManager
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()
                
                VStack(spacing: 20) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("Processing...")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("AI is analyzing and summarizing your content")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 15) {
                    ProgressView(value: summarizerState.progress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                        .scaleEffect(x: 1, y: 2, anchor: .center)
                    
                    Text("\(Int(summarizerState.progress * 100))%")
                        .font(.headline)
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
                        .foregroundColor(.red)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.red, lineWidth: 1)
                        )
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            }
            .navigationTitle("Summarizing")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Cancel") {
                        summarizerState.cancelSummarization()
                        isPresented = false
                    }
                }
            }
        }
        .onChange(of: summarizerState.state) { state in
            if state == .completed || state == .error || state == .idle {
                isPresented = false
            }
        }
    }
}

#Preview {
    SummarizeProgressView(isPresented: .constant(true))
        .environmentObject(SummarizerStateManager())
        .environmentObject(NavigationCoordinator())
}
