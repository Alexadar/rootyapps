// RecordWindow.swift — occlusion-proof single-window screen recorder (ScreenCaptureKit).
//
//   swiftc -O RecordWindow.swift -o recordwindow
//   ./recordwindow <windowID> <seconds> <out.mov>
//   ./recordwindow --pid <pid> <seconds> <out.mov>      # preferred
//
// Unlike `ffmpeg -f avfoundation` (whole-display only, so the terminal/dock/other windows
// leak in), SCContentFilter(desktopIndependentWindow:) records ONLY the given window's own
// composited content — even if something is on top of it. Get <windowID> from Quartz
// (CGWindowListCopyWindowInfo), never AppleScript. Needs Screen Recording permission on the
// terminal you run from (granted once).
//
// PREFER --pid. A windowID has to be looked up first, and every lookup key that isn't a pid —
// app name, window title, bundle id — is ambiguous the moment a second copy of the app is
// running, which is normal when several agents work at once. Launch the app yourself, keep $!,
// and record that process: it cannot resolve to somebody else's window.
import Foundation
import AVFoundation
import ScreenCaptureKit
import AppKit
import CoreMedia

// A plain CLI has no window-server connection → ScreenCaptureKit asserts CGS_REQUIRE_INIT.
// Bootstrapping AppKit as an accessory app gives it one.
_ = NSApplication.shared
NSApplication.shared.setActivationPolicy(.accessory)

let args = CommandLine.arguments
var winID: UInt32? = nil
var targetPID: pid_t? = nil
var seconds: Double = 0
var outPath = ""
if args.count == 5, args[1] == "--pid" {
    targetPID = pid_t(args[2]); seconds = Double(args[3]) ?? 0; outPath = args[4]
} else if args.count == 4 {
    winID = UInt32(args[1]); seconds = Double(args[2]) ?? 0; outPath = args[3]
}
guard (winID != nil || targetPID != nil), seconds > 0, !outPath.isEmpty else {
    FileHandle.standardError.write(Data(
        "usage: recordwindow (--pid <pid> | <windowID>) <seconds> <out.mov>\n".utf8))
    exit(2)
}
let outURL = URL(fileURLWithPath: outPath)

final class Recorder: NSObject, SCStreamOutput {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    private var started = false
    let done = DispatchSemaphore(value: 0)

    init(width: Int, height: Int, url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid else { return }
        // SCK emits blank "idle" frames with a non-.complete status — skip them or you get
        // black/flicker frames in the output.
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = arr.first?[.status] as? Int, SCFrameStatus(rawValue: raw) != .complete {
            return
        }
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sb))
            started = true
        }
        if input.isReadyForMoreMediaData { input.append(sb) }
    }

    func finish() {
        guard started else { done.signal(); return }
        input.markAsFinished()
        writer.finishWriting { self.done.signal() }
        done.wait()
    }
}

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let win: SCWindow
        if let targetPID {
            // Largest on-screen window owned by that process: the app's main window, never a
            // panel, a tooltip, or another copy of the same app.
            let owned = content.windows
                .filter { $0.owningApplication?.processID == targetPID
                          && $0.frame.width > 200 && $0.frame.height > 200 }
                .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
            guard let first = owned.first else {
                FileHandle.standardError.write(Data("no window for pid \(targetPID)\n".utf8)); exit(3)
            }
            win = first
        } else {
            guard let found = content.windows.first(where: { $0.windowID == winID }) else {
                FileHandle.standardError.write(Data("window \(String(describing: winID)) not found\n".utf8)); exit(3)
            }
            win = found
        }
        let scale = 2   // Retina
        let w = Int(win.frame.width) * scale, h = Int(win.frame.height) * scale
        let cfg = SCStreamConfiguration()
        cfg.width = w; cfg.height = h
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        cfg.showsCursor = false
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.queueDepth = 6
        let rec = try Recorder(width: w, height: h, url: outURL)
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: win),
                              configuration: cfg, delegate: nil)
        try stream.addStreamOutput(rec, type: .screen, sampleHandlerQueue: DispatchQueue(label: "rec.queue"))
        try await stream.startCapture()
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        try await stream.stopCapture()
        rec.finish()
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(4)
    }
}
RunLoop.main.run()
