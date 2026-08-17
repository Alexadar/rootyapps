// Mac only. The file is inside the shared `Studio/` source group, which both destinations compile,
// so the guard is what keeps `NSWorkspace` and `NSSharingServicePicker` out of the iOS build.
#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import RecipeKit
import EditsKit

/// Mac (`1h`): sidebar library, one glass toolbar, drag-and-drop import.
///
/// The Mac gets the third import path and two keyboard gestures the touch platforms cannot have:
/// **Space** holds the original (like Quick Look) and **⌘Z** reverts.
struct MacRoot: View {

    @Bindable var model: AppModel
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(LinearGradient(colors: ST.macPaper, startPoint: .top, endPoint: .bottom))
        // Drag-and-drop onto **any part of the window**, not a designated well.
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted { dropAffordance }
        }
        .sheet(isPresented: $model.isExporting) {
            ExportSheet(deviceName: "Mac") { model.export($0) }
        }
        .studioMessage($model.message)
        .studioShare($model.shareItem)
        // ⌘Z reverts. Registered here rather than in the editor so it is live whenever an edit is
        // open, including while the pointer is in the sidebar.
        .background {
            Button("Revert") { model.edit?.revert() }
                .keyboardShortcut("z", modifiers: .command)
                .hidden()
                .disabled(model.edit == nil)
        }
        // Space holds the original, and **releases it on key-up** — a toggle would leave the app
        // showing the original after a stray tap, which is exactly the confusion a hold avoids.
        .onKeyPress(keys: [.space], phases: [.down, .up]) { press in
            guard let edit = model.edit else { return .ignored }
            edit.comparison.isHoldingOriginal = (press.phase == .down)
            return .handled
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Library")
                .stFont(.footnote)
                .foregroundStyle(ST.ink3(.light))
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, ST.Space.grid)
                .padding(.vertical, ST.Space.tight)

            List(model.library.records, selection: Binding(
                get: { model.edit?.record.id },
                set: { id in
                    guard let record = model.library.records.first(where: { $0.id == id }) else { return }
                    model.open(record)
                }
            )) { record in
                HStack(spacing: ST.Space.gap) {
                    if let thumbnail = model.library.thumbnail(for: record) {
                        Image(cgImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 27)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.displayName).stFont(.caption)
                        Text(record.badge)
                            .stFont(.footnote, tabularNumbers: true)
                            .foregroundStyle(ST.ink3(.light))
                    }
                }
                .tag(record.id)
            }
            .listStyle(.sidebar)

            Divider()

            // Straight to the real folder. The library is a folder the user owns, and saying so is
            // cheaper than any amount of copy about privacy.
            Button {
                NSWorkspace.shared.open(model.location.root)
            } label: {
                Label("\(model.location.captionSuffix.capitalizedFirst). Open in Finder",
                      systemImage: "arrow.up.forward.app")
                    .stFont(.footnote)
            }
            .buttonStyle(.plain)
            .padding(ST.Space.gap)
            .accessibilityIdentifier("library.openInFinder")
        }
        .frame(minWidth: 220)
        .task { await model.library.reload() }
    }

    @ViewBuilder
    private var detail: some View {
        if let edit = model.edit {
            EditView(model: edit,
                     layout: .toolbar,
                     onExport: { model.isExporting = true },
                     onOpenLibrary: { model.closeEdit() })
        } else {
            ImportView { data, name in
                Task { await model.importPhoto(data: data, displayName: name) }
            }
        }
    }

    private var dropAffordance: some View {
        VStack(spacing: ST.Space.tight) {
            Text("Drop a photo anywhere")
                .stFont(.cardHeading)
            Text("to start a new enhancement. It stays on this Mac.")
                .stFont(.caption)
                .foregroundStyle(ST.ink2(.light))
        }
        .padding(ST.Space.section)
        .stGlassCard(.regular, radius: ST.Radius.frame)
        .overlay(
            RoundedRectangle(cornerRadius: ST.Radius.frame, style: .continuous)
                .strokeBorder(ST.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
        .transition(.opacity)
        .allowsHitTesting(false)
        .accessibilityIdentifier("mac.dropTarget")
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Two shapes arrive here: a file URL from Finder, and raw image data from an app that has
        // no file to give. Both are supported, because the one that is missing is always the one
        // the user tries first.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, let data = try? Data(contentsOf: url) else { return }
                Task { @MainActor in
                    await model.importPhoto(data: data,
                                            displayName: url.deletingPathExtension().lastPathComponent)
                }
            }
            return true
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data else { return }
            Task { @MainActor in
                await model.importPhoto(data: data, displayName: "Dropped photo")
            }
        }
        return true
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

#endif
