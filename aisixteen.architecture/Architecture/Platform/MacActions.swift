import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Mac-only actions.
///
/// ⚠️ There is deliberately **no "Set as Desktop"** here. The wallpaper app has it because the
/// deliverable there is a wallpaper. Here the deliverable is the image itself — a proposal for a
/// space — and offering to set your redesigned living room as your desktop picture would be a
/// borrowed feature from a different product.
enum MacActions {

    static func reveal(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }

    /// Export writes a PNG or HEIC to a folder the user chooses. The Mac's entitlements carry
    /// `files.user-selected.read-only`, so a save panel is the only way out — which is correct:
    /// the app should not be able to write anywhere the user has not pointed at.
    static func export(_ url: URL, suggestedName: String) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: url, to: destination)
        #endif
    }
}

/// Saving a redesign into the user's photo library.
enum ShareActions {
    #if os(iOS)
    static func saveToPhotos(_ url: URL) {
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
    #endif
}
