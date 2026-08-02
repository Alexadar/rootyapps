// CaptureWindow.swift — occlusion-proof, unambiguous single-window SCREENSHOT (ScreenCaptureKit).
//
//   swiftc -O CaptureWindow.swift -o capturewindow
//   ./capturewindow --pid 12345 --out shot.png
//   ./capturewindow --bundle com.example.App --title "Earth Around" --out shot.png
//   ./capturewindow --list                       # JSON of every candidate window
//
// WHY NOT `screencapture`: the system tool grabs a display region, so whatever happens to be in
// front lands in the image — a notification banner, another app, a second copy of this same app
// launched by a different agent. It also cannot see a window that is occluded or on another
// Space. SCContentFilter(desktopIndependentWindow:) asks the window server for THAT window's own
// composited content, so nothing on top of it can contaminate the capture.
//
// WHY --pid IS THE PRIMARY SELECTOR: bundle id and window title are NOT unique. Two agents each
// running their own copy of the same app produce two windows with identical bundle id and title,
// and picking "the first match" silently captures a coin flip. A pid is unique per process, so
// the caller launches the app, keeps the pid, and captures exactly that instance. See
// capture_mac_window.sh for the launch → wait → capture → kill-that-pid-only sequence.
//
// SAFETY: with no unambiguous match this EXITS NON-ZERO and captures nothing. A wrong screenshot
// that looks plausible is worse than no screenshot, because it ships.
//
// Needs Screen Recording permission for the terminal/agent shell it runs from (granted once,
// System Settings → Privacy & Security → Screen Recording).
import Foundation
import ScreenCaptureKit
import AppKit
import CoreImage

// A plain CLI has no window-server connection → ScreenCaptureKit asserts CGS_REQUIRE_INIT.
// Bootstrapping AppKit as an accessory app gives it one without showing a Dock icon.
_ = NSApplication.shared
NSApplication.shared.setActivationPolicy(.accessory)

struct Options {
    var pid: pid_t?
    var bundle: String?
    var title: String?
    var out: String?
    var scale: Double = 2.0        // Retina by default; App Store wants the @2x pixels
    var list = false
    var largest = false            // tie-break by area instead of failing on ambiguity
    var minSize: Double = 200      // ignore palettes, menu-bar extras, tooltips
}

func parse() -> Options {
    var o = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--pid":     o.pid = it.next().flatMap { pid_t($0) }
        case "--bundle":  o.bundle = it.next()
        case "--title":   o.title = it.next()
        case "--out":     o.out = it.next()
        case "--scale":   o.scale = it.next().flatMap(Double.init) ?? 2.0
        case "--min-size":o.minSize = it.next().flatMap(Double.init) ?? 200
        case "--list":    o.list = true
        case "--largest": o.largest = true
        default:
            FileHandle.standardError.write(Data("unknown argument: \(a)\n".utf8))
            exit(2)
        }
    }
    return o
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("capturewindow: \(message)\n".utf8))
    exit(1)
}

let opts = parse()

func describe(_ w: SCWindow) -> String {
    let app = w.owningApplication
    return """
    {"windowID":\(w.windowID),"pid":\(app?.processID ?? -1),\
    "bundle":"\(app?.bundleIdentifier ?? "")","app":"\(app?.applicationName ?? "")",\
    "title":"\((w.title ?? "").replacingOccurrences(of: "\"", with: "\\\""))",\
    "w":\(Int(w.frame.width)),"h":\(Int(w.frame.height))}
    """
}

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                          onScreenWindowsOnly: true)
        // Drop the chrome that is never the thing you meant: zero-size, tiny palettes, and
        // windows with no owning application.
        var candidates = content.windows.filter { w in
            w.owningApplication != nil
                && w.frame.width >= opts.minSize && w.frame.height >= opts.minSize
        }

        if opts.list {
            print("[" + candidates.map(describe).joined(separator: ",\n ") + "]")
            exit(0)
        }

        // Each filter is ANDed. pid is the one that actually disambiguates instances.
        if let pid = opts.pid {
            candidates = candidates.filter { $0.owningApplication?.processID == pid }
        }
        if let bundle = opts.bundle {
            candidates = candidates.filter { $0.owningApplication?.bundleIdentifier == bundle }
        }
        if let title = opts.title {
            candidates = candidates.filter { ($0.title ?? "").contains(title) }
        }
        guard opts.pid != nil || opts.bundle != nil || opts.title != nil else {
            fail("refusing to capture without a selector — pass --pid (preferred), --bundle or --title")
        }
        guard let out = opts.out else { fail("missing --out") }

        if candidates.isEmpty {
            fail("no window matched. Run --list to see candidates; if the app just launched, wait for its window to exist.")
        }
        if candidates.count > 1 && !opts.largest {
            let list = candidates.map(describe).joined(separator: "\n  ")
            fail("""
                 \(candidates.count) windows matched — refusing to guess which one you meant.
                   \(list)
                 Narrow it with --pid, or pass --largest to take the biggest.
                 """)
        }
        // Deterministic: largest area, then lowest windowID so repeat runs agree.
        let win = candidates.sorted {
            let a = $0.frame.width * $0.frame.height, b = $1.frame.width * $1.frame.height
            return a == b ? $0.windowID < $1.windowID : a > b
        }[0]

        let config = SCStreamConfiguration()
        config.width = Int(win.frame.width * opts.scale)
        config.height = Int(win.frame.height * opts.scale)
        config.showsCursor = false
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = true      // no drop shadow baked into the PNG
        config.backgroundColor = .clear

        let filter = SCContentFilter(desktopIndependentWindow: win)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                              configuration: config)

        let url = URL(fileURLWithPath: out)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { fail("could not create \(out)") }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { fail("could not write \(out)") }

        let note = "captured pid \(win.owningApplication?.processID ?? -1) "
            + "window \(win.windowID) (\(image.width)×\(image.height)) → \(out)\n"
        FileHandle.standardError.write(Data(note.utf8))
        exit(0)
    } catch {
        fail("\(error)")
    }
}

RunLoop.main.run()
