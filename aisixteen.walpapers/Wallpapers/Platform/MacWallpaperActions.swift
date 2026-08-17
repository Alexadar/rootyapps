#if os(macOS)
import SwiftUI
import AppKit
import LibraryKit
import GenerationKit

/// macOS: the app actually finishes the job.
///
/// `NSWorkspace.setDesktopImageURL(_:for:options:)` sets the desktop picture for a given screen,
/// immediately, from inside the sandbox — the file is one the app wrote in its own container, so no
/// user-selected access is needed. Click, done, no sheet and no instructions.
///
/// **What is not possible:** the design's *Every Space on this display* row. `setDesktopImageURL`
/// addresses an `NSScreen`, and Spaces are not individually addressable through any public API. It
/// is left out rather than shipped as a menu item that quietly does the same thing as the row above
/// it.
@MainActor
@Observable
final class MacWallpaperActions: WallpaperActions {

    enum Scope {
        case mainDisplay
        case allDisplays
    }

    var handoff: WallpaperHandoff?
    var scope: Scope = .mainDisplay

    let primaryActionTitle = "Set as Desktop"

    /// True when there is a second display, which is the only situation in which the *All displays*
    /// row is worth showing.
    var hasMultipleDisplays: Bool { NSScreen.screens.count > 1 }

    func performPrimary(on record: WallpaperRecord) async {
        setDesktop(record, scope: scope)
    }

    func setDesktop(_ record: WallpaperRecord, scope: Scope) {
        let screens: [NSScreen]
        switch scope {
        case .mainDisplay:  screens = [NSScreen.main].compactMap { $0 }
        case .allDisplays:  screens = NSScreen.screens
        }

        guard !screens.isEmpty else {
            handoff = WallpaperHandoff(succeeded: false, message: "No display to set.")
            return
        }

        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            // A generated wallpaper is made at the display's own aspect ratio, so filling is right
            // and cropping is minimal. Without this macOS letterboxes anything that is not an exact
            // match against the fill colour.
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true,
        ]

        do {
            for screen in screens {
                // Each display gets the master fitted to its own pixels. That is the payoff for not
                // cropping during generation: one wallpaper, correctly framed on a 16:10 laptop and
                // a 16:9 external at the same time.
                let url = Self.fitted(record, for: screen) ?? record.imageURL
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
            }
            handoff = nil          // nothing to explain; it is done
        } catch {
            handoff = WallpaperHandoff(succeeded: false,
                                       message: "macOS wouldn't accept that picture as a desktop image.")
        }
    }

    func share(_ record: WallpaperRecord) {
        guard let window = NSApp.keyWindow, let view = window.contentView else { return }
        let picker = NSSharingServicePicker(items: [record.imageURL])
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    func dismissHandoff() { handoff = nil }

    /// Writes a display-shaped copy beside the master, in a temporary file macOS can keep reading.
    @MainActor
    private static func fitted(_ record: WallpaperRecord, for screen: NSScreen) -> URL? {
        let pixels = AspectRatio(width: Int(screen.frame.width * screen.backingScaleFactor),
                                 height: Int(screen.frame.height * screen.backingScaleFactor))
        guard let data = try? Data(contentsOf: record.imageURL),
              let image = Bitmap.platformImage(pngData: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let fittedImage = WallpaperFitting.fitNatively(cg, to: pixels),
              let png = Bitmap.pngData(cg: fittedImage)
        else { return nil }

        // The desktop picture is read back by the system later, so it cannot be a file that
        // disappears when this function returns.
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(record.id)-\(pixels.width)x\(pixels.height).png")
        try? png.write(to: target, options: .atomic)
        return target
    }

    /// The generation size the Mac offers by default: the frontmost display's own resolution.
    ///
    /// A desktop wallpaper made at phone proportions and stretched across a 5K display is the thing
    /// that makes generated wallpapers look cheap, and it is entirely avoidable — the aspect ratio
    /// is an input to the model, not a crop applied afterwards.
    static func frontmostDisplayPixels() -> (width: Int, height: Int) {
        guard let screen = NSScreen.main else { return (3840, 2160) }
        let scale = screen.backingScaleFactor
        return (Int(screen.frame.width * scale), Int(screen.frame.height * scale))
    }
}
#endif
