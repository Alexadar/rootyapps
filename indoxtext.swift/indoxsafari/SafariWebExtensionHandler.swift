//
//  SafariWebExtensionHandler.swift
//  indoxsafari
//
//  Created by Oleksandr Koreniuk on 15.04.2022.
//

import SafariServices
import os.log

enum SafariExtentionEventTypes: String {
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
  

  private static var callLock = NSLock();
  
  private var indox: Indox {
    get {
      return SafariWebExtensionHandler.indox;
    }
  }
  
  private var callLock: NSLock {
    get {
      return SafariWebExtensionHandler.callLock;
    }
  }
  
  override init() {
    super.init()
  }
  
  private func prepareResponse() -> [String : String] {
    return [
      "status": String(self.indox.status.rawValue),
      "percentage": String(self.indox.percentage)
    ]
  }
  
  private func sendRespose(context: NSExtensionContext, responseData: [String:String]) -> Void {
    let response = NSExtensionItem()
    response.userInfo?[SFExtensionMessageKey] = responseData;
    context.completeRequest(returningItems: [response], completionHandler: nil)
  }
  
  func beginRequest(with context: NSExtensionContext) {
    let item = context.inputItems[0] as! NSExtensionItem
    let message = (item.userInfo?[SFExtensionMessageKey] as! CVarArg)
    let messageData = (message as! NSDictionary)
    let task = messageData["task"] as? String;
    let data = messageData["data"] as? String;
    var responseData = self.prepareResponse();
    self.callLock.lock()
    switch(task) {
    case SafariExtentionEventTypes.DoSumm.rawValue:
        if(self.indox.status == EngineState.OnIdle) {
          self.indox.summaryTextStart(
            textArg: data!,
            onComplete: { result in
              responseData["synopsys"] = result
              self.sendRespose(context: context, responseData: responseData);
            })
        }
      break;
    case SafariExtentionEventTypes.DoCancel.rawValue:
      if(self.indox.status == EngineState.OnWork) {
        self.indox.cancelSummarization();
      }
      self.sendRespose(context: context, responseData: responseData);
      break;
    case SafariExtentionEventTypes.GetStatus.rawValue:
      self.sendRespose(context: context, responseData: responseData);
      break;
    default:
      self.sendRespose(context: context, responseData: responseData);
      break;
    }
    self.callLock.unlock()
  }
  
}
