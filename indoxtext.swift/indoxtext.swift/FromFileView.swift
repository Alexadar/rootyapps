import SwiftUI
import UniformTypeIdentifiers

struct FromFileView: View {
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var summarizerState: SummarizerStateManager
    @State private var showingFilePicker = false
    @State private var showingProgressSheet = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select file to summarize")
                .font(.headline)
                .padding(.top)
            
            if let selectedFile = summarizerState.inputFile {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text(selectedFile.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text(selectedFile.type.uppercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
            } else {
                Button(action: {
                    showingFilePicker = true
                }) {
                    VStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Select File")
                            .font(.headline)
                            .foregroundColor(.blue)
                        
                        Text("Tap to choose a text or PDF file")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                }
            }
            
            if summarizerState.inputFile != nil {
                Button(action: {
                    showingFilePicker = true
                }) {
                    Text("Change File")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue, lineWidth: 1)
                        )
                }
            }
            
            Button(action: {
                summarizerState.startSummarization()
                showingProgressSheet = true
            }) {
                HStack {
                    Image(systemName: "doc.text")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text("Summarize file")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(summarizerState.inputFile == nil ? Color.gray : Color.blue)
                .cornerRadius(10)
            }
            .disabled(summarizerState.inputFile == nil)
            
            Spacer()
        }
        .padding()
        .navigationTitle("From file")
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.text, .pdf, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    let selectedFile = SelectedFile(
                        url: url,
                        name: url.lastPathComponent,
                        type: url.pathExtension
                    )
                    summarizerState.setInputFile(selectedFile)
                }
            case .failure(let error):
                print("File selection error: \(error)")
            }
        }
        .sheet(isPresented: $showingProgressSheet) {
            SummarizeProgressView(isPresented: $showingProgressSheet)
                .environmentObject(summarizerState)
                .environmentObject(navigationCoordinator)
        }
        .onChange(of: summarizerState.state) { state in
            if state == .completed {
                showingProgressSheet = false
                // Small delay to ensure sheet is dismissed before navigation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    navigationCoordinator.navigate(to: .result)
                }
            }
        }
        .onAppear {
            summarizerState.reset()
        }
    }
}

#Preview("From File - No File Selected") {
    NavigationView {
        FromFileView()
            .environmentObject(NavigationCoordinator())
            .environmentObject(SummarizerStateManager())
    }
}

#Preview("From File - With File Selected") {
    @Previewable @StateObject var summarizerState = {
        let manager = SummarizerStateManager()
        let tempURL = URL(fileURLWithPath: "/tmp/sample.pdf")
        manager.inputFile = SelectedFile(url: tempURL, name: "sample.pdf", type: "pdf")
        return manager
    }()

    NavigationView {
        FromFileView()
            .environmentObject(NavigationCoordinator())
            .environmentObject(summarizerState)
    }
}

#Preview("From File - Text File Selected") {
    @Previewable @StateObject var summarizerState = {
        let manager = SummarizerStateManager()
        let tempURL = URL(fileURLWithPath: "/tmp/document.txt")
        manager.inputFile = SelectedFile(url: tempURL, name: "document.txt", type: "txt")
        return manager
    }()

    NavigationView {
        FromFileView()
            .environmentObject(NavigationCoordinator())
            .environmentObject(summarizerState)
    }
}
