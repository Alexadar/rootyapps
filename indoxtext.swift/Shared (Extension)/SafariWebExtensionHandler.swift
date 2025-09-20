//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Created by Oleksandr Koreniuk on 20.09.2025.
//

import SafariServices
import os.log

enum SafariExtensionEventTypes: String {
    case GetStatus = "GetStatus"
    case DoCancel = "DoCancel"
    case DoSumm = "DoSumm"
}

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    
    #if targetEnvironment(macCatalyst) || os(macOS)
    private static var indox = Indox(
        vectorizerThreads: 2,
        predictThreads: 8,
        batch_size: 64,
        min_sen_width: 75,
        max_queue_count: 800,
        max_tokenized_sen_len: 253
    )
    #else
    private static var indox = Indox(
        vectorizerThreads: 2,
        predictThreads: 2,
        batch_size: 64,
        min_sen_width: 75,
        max_queue_count: 100,
        max_tokenized_sen_len: 64
    )
    #endif
    
    private static var callLock = NSLock()
    
    private var indox: Indox {
        get {
            return SafariWebExtensionHandler.indox
        }
    }
    
    private var callLock: NSLock {
        get {
            return SafariWebExtensionHandler.callLock
        }
    }
    
    override init() {
        super.init()
    }
    
    private func prepareResponse() -> [String: String] {
        return [
            "status": String(self.indox.status.rawValue),
            "percentage": String(self.indox.percentage)
        ]
    }
    
    private func sendResponse(context: NSExtensionContext, responseData: [String: String]) -> Void {
        let response = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            response.userInfo = [SFExtensionMessageKey: responseData]
        } else {
            response.userInfo = ["message": responseData]
        }
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems[0] as! NSExtensionItem
        
        let message: Any?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = item.userInfo?[SFExtensionMessageKey]
        } else {
            message = item.userInfo?["message"]
        }
        
        guard let messageData = message as? NSDictionary else {
            let response = prepareResponse()
            sendResponse(context: context, responseData: response)
            return
        }
        
        let task = messageData["command"] as? String
        let data = messageData["data"] as? [String: Any]
        var responseData = self.prepareResponse()
        
        self.callLock.lock()
        defer { self.callLock.unlock() }
        
        switch task {
        case SafariExtensionEventTypes.DoSumm.rawValue:
            if self.indox.status == EngineState.OnIdle {
                if let htmlData = data?["innerHtml"] as? String {
                    // Extract text from HTML
                    let extractedText = extractTextFromHTML(htmlData)
                    
                    self.indox.summaryTextStart(
                        textArg: extractedText,
                        onComplete: { result in
                            responseData["synopsys"] = result
                            self.sendResponse(context: context, responseData: responseData)
                        })
                } else {
                    self.sendResponse(context: context, responseData: responseData)
                }
            } else {
                self.sendResponse(context: context, responseData: responseData)
            }
            
        case SafariExtensionEventTypes.DoCancel.rawValue:
            if self.indox.status == EngineState.OnWork {
                self.indox.cancelSummarization()
            }
            self.sendResponse(context: context, responseData: responseData)
            
        case SafariExtensionEventTypes.GetStatus.rawValue:
            self.sendResponse(context: context, responseData: responseData)
            
        default:
            self.sendResponse(context: context, responseData: responseData)
        }
    }
    
    private func extractTextFromHTML(_ html: String) -> String {
        // Simple HTML text extraction - remove tags and decode entities
        var text = html
        
        // Remove script and style content
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression, range: nil)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression, range: nil)
        
        // Remove HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression, range: nil)
        
        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        
        // Clean up whitespace
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression, range: nil)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return text
    }
}
