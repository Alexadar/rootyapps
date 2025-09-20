//
//  Indox.swift
//  indox
//
//  Created by Oleksandr Korenyuk on 13.10.2021.
//

import Foundation
import CoreML
import NaturalLanguage
import PDFKit

internal struct SentencePair {
  public var s1: String
  public var s2: String
  public var i: Int
  public var k: Int
  public var file_index: Int
}

internal typealias ResultsType = (Int, Int, Float);

public class SyncArray<T> {
  
  private var dataArray = [T]()
  
  private var lockArr = NSLock()
  
  public init() {
    
  }
  
  public func reset() {
    dataArray = []
  }
  
  public func count() -> Int {
    var count = 0;
    count = dataArray.count
    return count;
  }
  
  public func pop() -> T? {
    var lastEl:T? = nil
    lockArr.lock()
    if(dataArray.count > 0){
      lastEl = dataArray.popLast()
    }
    lockArr.unlock()
    return lastEl;
  }
  
  public func append(value: T) -> Void {
    lockArr.lock()
    dataArray.append(value)
    lockArr.unlock()
  }
}

enum OnSummEventTypes: Int {
  case OnIdle = 0
  case OnStart = 1
  case OnLog = 2
  case OnProgress = 3
  case OnStop = 4
  case OnError = 5
  case OnCancel = 6
}

enum EngineState: Int {
  case OnIdle = 0
  case OnWork = 1
  case OnCancelling = 2
}


typealias OnComplete = ((_ synopsys: String) -> Void)?;
typealias OnLog = ((_ name: String, _ body: [String:Any]) -> Void)?;

class Indox {
  
  private var statusLock = NSLock()
  private var percentageLock = NSLock()
  
  private var onLog: OnLog = nil;
  private var onComplete: OnComplete = nil;
  
  private func log(logVal: String, type: OnSummEventTypes = OnSummEventTypes.OnLog, dataVal: [String:Any] = [String:Any]()) {
    var eventData : [String:Any] = [String:Any]()
    eventData["type"] = type.rawValue;
    eventData["text"] = logVal;
    eventData["data"] = dataVal;
    (self.onLog ?? {_,_ in })("OnSumm", eventData)
    print(logVal)
  }
  
  private var workerThreadPtrs:[DispatchWorkItem] = [];
  
  public static let pairsQueue = SyncArray<[SentencePair]>();
  public static let vectorQueue = SyncArray<VectorContainerML>();
  public static let resultsQueue = SyncArray<[ResultsType]>();
  
  
  private let vectorizerThreads: Int;
  private let predictThreads: Int;
  private let batch_size: Int;
  private let min_sen_width: Int;
  private let max_queue_count: Int;
  private let max_tokenized_sen_len: Int;
  private let min_sen_proc_count: Int;
  
  private var _status = EngineState.OnIdle;
  
  public var status: EngineState {
    get {
      return self._status;
    }
    set(newVal) {
      statusLock.lock()
      self._status = newVal;
      statusLock.unlock()
    }
  }
  
  private var _percentage = 0;
  
  public var percentage: Int {
    get {
      return self._percentage;
    }
    set(newVal) {
      percentageLock.lock()
      self._percentage = newVal;
      percentageLock.unlock()
    }
  }
  
  public init(
    onLog: @escaping (_ name: String, _ body: [String:Any]) -> () = {_,_  in },
    onComplete: @escaping (_ synopsys: String) -> () = {_ in },
    
    vectorizerThreads: Int = 1,
    predictThreads: Int = 1,
    batch_size: Int = 1,
    min_sen_width: Int = 75,
    max_queue_count: Int = 10,
    max_tokenized_sen_len: Int = 64,
    min_sen_proc_count: Int = 5
  ) {
    self.onLog = onLog;
    self.onComplete = onComplete;
    
    self.vectorizerThreads = vectorizerThreads;
    self.predictThreads = predictThreads;
    self.batch_size = batch_size;
    self.min_sen_width = min_sen_width;
    self.max_queue_count = max_queue_count;
    self.max_tokenized_sen_len = max_tokenized_sen_len;
    self.min_sen_proc_count = min_sen_proc_count;
  }
  
  public func cancelSummarization() -> Void {
    if(self.workerThreadPtrs.count > 0 && self.status == EngineState.OnWork) {
      self.status = EngineState.OnCancelling
      DispatchQueue.main.async {
        print("Cancelling...")
        for i in 0...self.workerThreadPtrs.count-1 {
          self.workerThreadPtrs[i].wait();
          print("Cancelled \(i+1) of \(self.workerThreadPtrs.count)")
        }
        
        self.log(logVal: "Canceled", type: OnSummEventTypes.OnCancel);
        self.status = EngineState.OnWork;
        self.workerThreadPtrs = []
        self.status = EngineState.OnIdle;
        self.percentage = 0;
      }
    }
  }
  
  // --- UPDATED: Accepts URL directly, not path string ---
  public func summaryFileStart(url: URL) -> Void {
    if(self.status == EngineState.OnIdle) {
      do {
        var isAccessing = false
        #if os(macOS)
        // Security-scoped URLs (if needed, mostly app store builds)
        isAccessing = url.startAccessingSecurityScopedResource()
        #endif
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if let pdf = PDFDocument(url: url) {
          let pageCount = pdf.pageCount
          let documentContent = NSMutableAttributedString()
          
          for i in 0 ..< pageCount {
            guard let page = pdf.page(at: i) else { continue }
            guard let pageContent = page.attributedString else { continue }
            documentContent.append(pageContent)
          }
          self.summaryTextStart(textArg: documentContent.string)
        } else {
          //All text files
          let textArg = try String(contentsOf: url, encoding: .utf8)
          self.summaryTextStart(textArg: textArg)
        }
      } catch {
        //TODO: Error handle
        print(error)
        self.log(
          logVal: "File open error: \(error.localizedDescription)",
          type: OnSummEventTypes.OnError,
          dataVal: [
            "error": error.localizedDescription
          ])
        self.status = EngineState.OnIdle;
        self.percentage = 0;
      }
    }
  }
  
  // ...the rest of the file remains unchanged except for summaryFileStart above...
  // (No changes needed elsewhere in this file)
  // ...PASTE THE REMAINDER OF THE FILE HERE, UNCHANGED...
  
  // The rest of your code is unchanged
  // (See original code above for full details)
}
