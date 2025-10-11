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

  public func summaryTextStart(
    textArg: String,
    onComplete: OnComplete = nil
  ) -> Void {
    if(self.status == EngineState.OnIdle) {
      self.status = EngineState.OnWork;
      self.percentage = 0
      self.workerThreadPtrs = []
      //create threads
      self.summaryText(textArg: textArg)
      //run threads
      if(self.workerThreadPtrs.count > 0) {
        for i in 0...self.workerThreadPtrs.count - 1 {
          let thread = self.workerThreadPtrs[i]
          DispatchQueue.global().async(execute: thread)
        }
      }
      self.onComplete = onComplete;
    }
  }

  private func summaryText(textArg: String) -> Void {
    self.log(logVal: "Started", type: OnSummEventTypes.OnStart)

    var text = textArg;

    Indox.pairsQueue.reset()
    Indox.resultsQueue.reset()
    Indox.vectorQueue.reset()

    while let rangeToReplace = text.range(of: "\n") {
      text.replaceSubrange(rangeToReplace, with: " ")
    }

    self.log(logVal: "Break sentences")

    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text

    var sentences:[String] = []

    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
      let sentence = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines);
      if(sentence.count > min_sen_width && sentence.last!.isPunctuation) {
        sentences.append(sentence)
      }
      return true
    }

    if(sentences.count<=min_sen_proc_count) {
      self.log(
        logVal: "Does not processed",
        type: OnSummEventTypes.OnStop,
        dataVal: [
          "synopsys": textArg,
          "took": 0
        ])
      (self.onComplete ?? {_ in })(textArg)
      self.status = EngineState.OnIdle;
      self.percentage = 0;
      return;
    }

    self.log(logVal: "Sentences count \(sentences.count)")

    self.log(logVal: "Tokenize")

    let totalBatches = Int(ceil(CGFloat(sentences.count*sentences.count) / CGFloat(batch_size)));

    func vectorizeML (batch: [SentencePair], bertTokenizer: BertTokenizer) -> VectorContainerML {
      var input = [sentenceModelInput]()
      var meta = [Meta]()
      for element in batch {
        let (input_ids, input_mask, segment_ids) = bertTokenizer.vectorize(
          s1: element.s1,
          s2: element.s2,
          max_sentence_len: max_tokenized_sen_len
        )
        input.append(sentenceModelInput(
          input_ids_1: ConvertToMLMultiArray(from: input_ids),
          input_mask_1: ConvertToMLMultiArray(from: input_mask),
          segment_ids_1: ConvertToMLMultiArray(from: segment_ids)))
        meta.append(Meta(
          i: element.i,
          k: element.k,
          file_index: element.file_index)
        )
      }
      return VectorContainerML(input: input, meta: meta);
    }

    func ConvertToMLMultiArray(from array: [Int]) -> MLMultiArray {
      let length = NSNumber(value: array.count)

      // Define shape of array
      guard let mlMultiArray = try? MLMultiArray(shape:[1, length], dataType:MLMultiArrayDataType.int32) else {
        fatalError("Unexpected runtime error. MLMultiArray")
      }

      // Insert elements
      for (index, element) in array.enumerated() {
        mlMultiArray[index] = element as NSNumber
      }

      return mlMultiArray
    }

    self.log(logVal: "Load model")

    self.log(logVal: "Pair")
    let start = DispatchTime.now()
    //Push results
    let workerThreadPtrPushResults = DispatchWorkItem {
      var pairs = [SentencePair]()
      var counterPairs = 0
      for i in 0...sentences.count-1 {
        for k in 0...sentences.count-1 {
          if(Indox.pairsQueue.count() > self.max_queue_count && self.status == EngineState.OnWork) {
            sleep(1)
          }
          if(self.status != EngineState.OnWork) {
            return;
          }
          pairs.append(SentencePair(s1: sentences[i], s2: sentences[k], i: i, k: k, file_index: 0))
          counterPairs+=1
          if(pairs.count == self.batch_size || (i==sentences.count-1 && k==sentences.count-1)) {
            Indox.pairsQueue.append(value: pairs)
            pairs = [];
          }
        }
      }
      self.log(logVal: "Pairing done \(counterPairs)")
    }
    self.workerThreadPtrs.append(workerThreadPtrPushResults)

    // synopsys

    struct SynopsysCont {
      let sen: String;
      let nextMax: Float;
      let idx: Int;
      public init(sen: String, nextMax: Float, idx: Int) {
        self.sen = sen;
        self.nextMax = nextMax;
        self.idx = idx;
      }
    }

    func synopsys_descend_down(n:Int , texts: [String], memory:[[Float]], forgetTreshold:Float=0.85) -> [SynopsysCont] {
      var currentTreshold:Float = 1
      var currentSentence = n
      var sequence = [SynopsysCont]()
      while (currentTreshold > forgetTreshold) && (currentSentence > 1) {
        // select available memories - all previous to n sentences, but what are in the past
        let availableMemories = memory.map { $0[currentSentence] }[0...currentSentence - 1]
        // looking best memory, tied to n sentence
        let nextMax = Array(availableMemories).max()
        let nextMaxIndex = availableMemories.firstIndex(of: nextMax!)
        currentSentence = nextMaxIndex!
        currentTreshold = nextMax!
        // best previous memory will be put to array start
        sequence.insert(SynopsysCont(sen: texts[nextMaxIndex!], nextMax: nextMax!, idx: currentSentence), at: 0)
      }
      return sequence
    }


    func synopsys_descend_up(n:Int , texts: [String], memory:[[Float]], forgetTreshold:Float=0.85) -> [SynopsysCont] {
      var currentTreshold:Float = 1
      var currentSentence = n
      var sequence = [SynopsysCont]()
      while (currentTreshold > forgetTreshold) && (currentSentence < texts.count - 1) {
        // select available memories - all after to n sentences, but what are in the future
        // find most connected sentence from future memories
        let availableMemories = memory.map { $0[currentSentence + 1...texts.count-1] }[currentSentence]
        // looking best memory, tied to n sentence
        let nextMax = Array(availableMemories).max()
        let nextMaxIndex = availableMemories.firstIndex(of: nextMax!)!
        currentSentence = nextMaxIndex
        currentTreshold = nextMax!
        // best previous memory will be put to array end
        sequence.append(SynopsysCont(sen: texts[nextMaxIndex], nextMax: nextMax!, idx: currentSentence))
      }
      return sequence
    }

    func synopsys(n:Int , texts: [String], memory:[[Float]], forgetTreshold:Float=0.85) -> [SynopsysCont] {
      let sequenceBeyound = synopsys_descend_down(n:n, texts:texts, memory:memory, forgetTreshold:forgetTreshold)
      let sequenceAbove = synopsys_descend_up(n:n, texts:texts, memory:memory, forgetTreshold:forgetTreshold)
      let sequence = sequenceBeyound + [SynopsysCont(sen: texts[n], nextMax: 0, idx:n)] + sequenceAbove
      return sequence
    }

    func synopsyses(lines: [String], memory: [[Float]], get_last_sentences_count:Int=1, forgetTreshold:Float=0.85) throws -> [[String]] {

      for i in 0...memory.count-1 {
        for k in 0...memory.count-1 {
          if memory[i][k] == 0 {
            throw NSError(domain: "Synposys calc", code: 1, userInfo: ["message": "Memory at i \(i),k \(k) is zero."] )
          }
        }
      }

      let allSums = memory.map { $0.reduce(0,+) };
      var sequences = [[String]]()
      var indexedSums = [(val:Float, idx:Int)]()
      for i in 0...allSums.count-1 {
        indexedSums.append((val:allSums[i], idx:i))
      }

      indexedSums = indexedSums.sorted(by: {$0.val > $1.val}) // reverse sort

      var allreadyInSequence = [Int]()

      // looking for tops
      for i in 0...indexedSums.count-1 {
        if sequences.count >= get_last_sentences_count{
          break
        }
        // get index of top sentence
        let cur = indexedSums[i].idx
        // descend and ascend around top sentence
        let curSequence = synopsys(n: cur, texts: lines, memory: memory, forgetTreshold:forgetTreshold)
        let newSequenceIndexes = curSequence.map { $0.idx }
        let intersect = Set(allreadyInSequence).intersection(Set(newSequenceIndexes))
        if intersect.count == 0 {
          sequences.append(curSequence.map { $0.sen })
          for e in newSequenceIndexes {
            allreadyInSequence.append(e)
          }
        }
      }

      return sequences
    }

    // synopsys

    //Get results
    var resultCount = 0
    var memory = [[Float]]()
    for i in 0...sentences.count-1 {
      memory.append([])
      for _ in 0...sentences.count-1 {
        memory[i].append(0)
      }
    }
    let workerThreadPtrGetResults = DispatchWorkItem {
      var progress = 0.0;
      while(resultCount < totalBatches) {

        if(self.status != EngineState.OnWork) {
          return;
        }
        let predictions = Indox.resultsQueue.pop()
        if predictions == nil {
          sleep(1)
        } else {
          resultCount = resultCount+1
          for pred in predictions! {
            memory[pred.0][pred.1] = pred.2
          }
        }
        progress = round(100*Double(resultCount)/Double(totalBatches))
        self.percentage = Int(progress)
        self.log(
          logVal: "Got results \(resultCount) of \(totalBatches). Progress \(progress)%",
          type: OnSummEventTypes.OnProgress,
          dataVal: [
            "progress": progress
          ])

      }
      self.log(
        logVal: "END Got results \(resultCount) of \(totalBatches). Progress \(progress)%",
        type: OnSummEventTypes.OnProgress,
        dataVal: [
          "progress": progress
        ])
      let synopsys = try! synopsyses(lines: sentences, memory: memory)

      self.log(logVal: "DONE")
      let end = DispatchTime.now()
      let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds // <<<<< Difference in nano seconds (UInt64)
      let timeInterval = Double(nanoTime) / 1_000_000_000 // Technically could overflow for long running tests
      let synopsysResult = synopsys[0].joined(separator: " ");
      self.log(logVal: "Time to process \(timeInterval) seconds")
      self.log(
        logVal: "Finished",
        type: OnSummEventTypes.OnStop,
        dataVal: [
          "synopsys": synopsysResult,
          "took": String(timeInterval)
        ])
      (self.onComplete ?? {_ in })(synopsysResult)
      self.status = EngineState.OnIdle;
      self.percentage = 0;
    }
    self.workerThreadPtrs.append(workerThreadPtrGetResults)

    // Vectorizer
    var vecCounter = 0
    for _ in (1 ... vectorizerThreads) {
      let vectorizerThread = DispatchWorkItem {
        let bertTokenizer = BertTokenizer();
        while(vecCounter<totalBatches) {

          if(Indox.vectorQueue.count() > self.max_queue_count && self.status == EngineState.OnWork) {
            sleep(1)
          }
          if(self.status != EngineState.OnWork) {
            return;
          }
          let batch = Indox.pairsQueue.pop()
          if batch != nil {
            autoreleasepool {
              let vectored = vectorizeML(batch: batch!, bertTokenizer: bertTokenizer);
              Indox.vectorQueue.append(value: vectored)
              vecCounter=vecCounter+1;
            }
          } else {
            sleep(1)
          }
        }
        self.log(logVal: "Vectored")
      }
      self.workerThreadPtrs.append(vectorizerThread)

    }

    // Predictor
    var predCounter = 0;
    for _ in (1 ... predictThreads) {
      let predictorThread = DispatchWorkItem {
        let model = try! sentenceModel()
        while(predCounter < totalBatches) {
          if(self.status != EngineState.OnWork) {
            return;
          }
          let batch = Indox.vectorQueue.pop()
          if batch != nil {
            let predictions = try! model.predictions(inputs: batch!.input)
            var predictionsMap = [ResultsType]()
            for i in 0...batch!.input.count-1 {
              predictionsMap.append((batch!.meta[i].i, batch!.meta[i].k, Float(truncating: predictions[i].loss_Softmax[1])))
            }
            Indox.resultsQueue.append(value: predictionsMap)
            predCounter=predCounter+1;
          } else {
            sleep(1)
          }
        }
        self.log(logVal: "Predicted")
      }
      self.workerThreadPtrs.append(predictorThread)
    }
  }

}
