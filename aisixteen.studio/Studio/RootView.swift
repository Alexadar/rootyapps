import SwiftUI
import Observation
import RecipeKit
import EditsKit

/// Everything the app is, above one photo.
@MainActor
@Observable
final class AppModel {

    var section: AppSection = .enhance
    private(set) var library: LibraryModel
    private(set) var edit: EditModel?
    var isExporting = false
    var message: String?

    let location: StorageLocation

    init(location: StorageLocation) {
        self.location = location
        self.library = LibraryModel(location: location,
                                    library: LibraryLocator.library(for: location,
                                                                    appVersion: LibraryLocator.appVersion))
    }

    /// Resolving the ubiquity container talks to the sync daemon and blocks for hundreds of
    /// milliseconds on first use, so it happens off the main actor and the app is built from the
    /// answer rather than waiting for it on screen.
    static func make() async -> AppModel {
        let location = await Task.detached(priority: .userInitiated) {
            LibraryLocator.resolve()
        }.value
        return AppModel(location: location)
    }

    func importPhoto(data: Data, displayName: String) async {
        guard let (record, image) = await library.importPhoto(data: data, displayName: displayName)
        else {
            message = "That file isn't an image this app can open."
            return
        }
        edit = EditModel(original: image, record: record, library: library.editLibrary)
        section = .enhance
    }

    func open(_ record: EditRecord) {
        guard let image = library.open(record) else {
            message = "That photo hasn't finished downloading from iCloud yet."
            return
        }
        edit = EditModel(original: image, record: record, library: library.editLibrary)
        section = .enhance
    }

    func closeEdit() {
        edit = nil
        section = .library
    }

    func export(_ option: ExportOption) {
        guard let edit, let data = edit.exportData() else { return }
        switch option {
        case .saveAsNew:
            Task {
                do {
                    try await PhotosWriter.saveAsNewPhoto(data)
                    message = "Saved. Your original is untouched."
                } catch {
                    message = PhotosWriter.deniedMessage
                }
            }
        case .share:
            shareItem = data
        }
    }

    /// Set when the share sheet should come up; cleared when it closes.
    var shareItem: Data?

    var deviceNoun: String {
        #if os(macOS)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
}

/// Picks the shell. One app, three genuinely different layouts (`1a`–`1h`) — not one layout
/// stretched.
struct RootView: View {

    @State private var model: AppModel?

    var body: some View {
        Group {
            if let model {
                shell(model)
                    .environment(\.stAccessibility, AccessibilityMode.standard)
                    .modifier(AccessibilityModeReader())
            } else {
                // The launch state is the canvas, not a spinner: resolving iCloud takes a moment and
                // a spinner would make a fast path look like a slow one.
                LinearGradient(colors: ST.canvasGradient, startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
        }
        .task {
            guard model == nil else { return }
            let created = await AppModel.make()
            // DEBUG-only, and only when the launch environment asks: brings a photo in without the
            // out-of-process picker, so the UI suite can drive the actual flow. The `#if` matters —
            // `FixturePhoto` does not exist in a Release build at all.
            #if DEBUG
            if FixturePhoto.isRequested, let data = FixturePhoto.data() {
                await created.importPhoto(data: data, displayName: "IMG_4021")
            }
            #endif
            model = created
        }
    }

    @ViewBuilder
    private func shell(_ model: AppModel) -> some View {
        #if os(macOS)
        MacRoot(model: model)
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            PadRoot(model: model)
        } else {
            PhoneRoot(model: model)
        }
        #endif
    }
}
