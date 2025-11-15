import SwiftUI
import Combine

enum SummarizeState {
    case idle
    case progress
    case completed
    case error
}

struct SelectedFile {
    let url: URL
    let name: String
    let type: String
    var thumbnail: String?
}

class SummarizerStateManager: ObservableObject {
    @Published var state: SummarizeState = .idle
    @Published var inputText: String = ""
    @Published var inputFile: SelectedFile?
    @Published var result: String = ""
    @Published var progress: Double = 0.0
    @Published var error: String?
    
    private var indoxEngine: Indox?
    
    init() {
        setupIndoxEngine()
    }
    
    private func setupIndoxEngine() {
        indoxEngine = Indox(
            onLog: { [weak self] name, body in
                DispatchQueue.main.async {
                    self?.handleIndoxEvent(name: name, body: body)
                }
            },
            onComplete: { [weak self] synopsis in
                DispatchQueue.main.async {
                    self?.result = synopsis
                    self?.state = .completed
                    self?.progress = 0.0
                }
            },
            vectorizerThreads: 16,
            predictThreads: 8,
            batch_size: 64,
            min_sen_width: 75,
            max_queue_count: 100,
            max_tokenized_sen_len: 253
        )
    }
    
    private func handleIndoxEvent(name: String, body: [String: Any]) {
        guard let eventType = body["type"] as? Int else { return }
        
        switch eventType {
        case OnSummEventTypes.OnStart.rawValue:
            state = .progress
            progress = 0.0
        case OnSummEventTypes.OnProgress.rawValue:
            if let data = body["data"] as? [String: Any],
               let progressValue = data["progress"] as? Double {
                progress = progressValue / 100.0
            }
        case OnSummEventTypes.OnStop.rawValue:
            if let data = body["data"] as? [String: Any],
               let synopsis = data["synopsys"] as? String {
                result = synopsis
                state = .completed
                progress = 0.0
            }
        case OnSummEventTypes.OnError.rawValue:
            state = .error
            error = body["text"] as? String ?? "Unknown error occurred"
            progress = 0.0
        case OnSummEventTypes.OnCancel.rawValue:
            state = .idle
            progress = 0.0
        default:
            break
        }
    }
    
    func setInputText(_ text: String) {
        inputText = text
        inputFile = nil
    }
    
    func setInputFile(_ file: SelectedFile) {
        inputFile = file
        inputText = ""
    }
    
    func startSummarization() {
        guard let engine = indoxEngine else { return }
        
        if !inputText.isEmpty {
            engine.summaryTextStart(textArg: inputText)
        } else if let file = inputFile {
            engine.summaryFileStart(url: file.url)
        }
    }
    
    func cancelSummarization() {
        indoxEngine?.cancelSummarization()
    }
    
    func reset() {
        state = .idle
        inputText = ""
        inputFile = nil
        result = ""
        progress = 0.0
        error = nil
    }
}
