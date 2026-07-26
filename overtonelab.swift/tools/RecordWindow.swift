// RecordWindow.swift — record a single macOS window (occlusion-proof) via ScreenCaptureKit.
// Only that window's content is captured — no other windows leak in (unlike avfoundation,
// which can only grab a whole display).  Needs Screen Recording permission.
//
//   swiftc -O RecordWindow.swift -o recordwindow
//   ./recordwindow <windowID> <seconds> <out.mov>
import Foundation
import AppKit
import ScreenCaptureKit
import AVFoundation
import CoreMedia

// Bootstrap a window-server connection (ScreenCaptureKit needs the process to be a GUI app,
// otherwise CoreGraphics asserts CGS_REQUIRE_INIT).
_ = NSApplication.shared
NSApplication.shared.setActivationPolicy(.accessory)

guard CommandLine.arguments.count == 4,
      let widRaw = UInt32(CommandLine.arguments[1]),
      let seconds = Double(CommandLine.arguments[2]) else {
    FileHandle.standardError.write(Data("usage: recordwindow <windowID> <seconds> <out.mov>\n".utf8)); exit(2)
}
let windowID = CGWindowID(widRaw)
let outURL = URL(fileURLWithPath: CommandLine.arguments[3])
try? FileManager.default.removeItem(at: outURL)

final class Recorder: NSObject, SCStreamOutput {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    private var started = false
    init(width: Int, height: Int, url: URL) throws {
        writer = try AVAssetWriter(url: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        super.init()
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid, CMSampleBufferGetImageBuffer(sb) != nil else { return }
        // Only append "complete" frames (skip blank/idle status frames).
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let statusRaw = arr.first?[.status] as? Int, let status = SCFrameStatus(rawValue: statusRaw),
           status != .complete { return }
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sb))
            started = true
        }
        if input.isReadyForMoreMediaData { input.append(sb) }
    }
}

let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let win = content.windows.first(where: { $0.windowID == windowID }) else {
            FileHandle.standardError.write(Data("window \(windowID) not found\n".utf8)); exit(3)
        }
        let scale = 2
        let w = Int(win.frame.width) * scale, h = Int(win.frame.height) * scale
        let rec = try Recorder(width: w, height: h, url: outURL)
        let cfg = SCStreamConfiguration()
        cfg.width = w; cfg.height = h
        cfg.showsCursor = false
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: win), configuration: cfg, delegate: nil)
        try stream.addStreamOutput(rec, type: .screen, sampleHandlerQueue: DispatchQueue(label: "rec"))
        try await stream.startCapture()
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        try await stream.stopCapture()
        rec.input.markAsFinished()
        await rec.writer.finishWriting()
        FileHandle.standardError.write(Data("ok \(w)x\(h)\n".utf8))
        sem.signal()
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(4)
    }
}
sem.wait()
