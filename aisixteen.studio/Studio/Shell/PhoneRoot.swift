import SwiftUI
import RecipeKit

/// iPhone (`1a`–`1f`): the photo full-bleed, the segment shell floating at the bottom.
struct PhoneRoot: View {

    @Bindable var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            // ⚠️ One `GlassEffectContainer`, not a `TabView` — and hidden while editing, because the
            // photo is the subject and a tab bar over it would be chrome competing with content.
            if model.edit == nil {
                SectionShell(selection: $model.section)
                    .padding(.bottom, ST.Space.tight)
            }
        }
        .sheet(isPresented: $model.isExporting) {
            ExportSheet(deviceName: model.deviceNoun) { model.export($0) }
        }
        .studioMessage($model.message)
        .studioShare($model.shareItem)
    }

    @ViewBuilder
    private var content: some View {
        if let edit = model.edit {
            EditView(model: edit,
                     layout: .stacked,
                     onExport: { model.isExporting = true },
                     onOpenLibrary: { model.closeEdit() })
        } else {
            switch model.section {
            case .enhance:
                ImportView { data, name in
                    Task { await model.importPhoto(data: data, displayName: name) }
                }
            case .library:
                LibraryView(model: model.library,
                            onOpen: { model.open($0) },
                            onImport: { model.section = .enhance })
            }
        }
    }
}

/// A transient line of feedback — "Saved. Your original is untouched."
///
/// A toast rather than an alert: nothing here needs a decision, and an alert would make saving a
/// photo feel like an event that went wrong.
private struct MessageModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message {
                Text(message)
                    .stFont(.caption)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, ST.Space.grid)
                    .padding(.vertical, ST.Space.tight)
                    .stGlassCapsule(.regular)
                    .padding(.top, ST.Space.tight)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier("app.message")
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation { self.message = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: message)
    }
}

extension View {
    func studioMessage(_ message: Binding<String?>) -> some View {
        modifier(MessageModifier(message: message))
    }
}
