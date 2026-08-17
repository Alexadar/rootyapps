import SwiftUI

/// iPad (`1g`): same components, re-flowed.
///
/// The bottom cluster becomes a floating **right column** so the photo keeps the full canvas height,
/// and the segment shell moves to the top centre, which is the iPadOS convention. Apple Pencil maps
/// to the Brush scope directly (`PencilScope`).
struct PadRoot: View {

    @Bindable var model: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            content

            if model.edit == nil {
                SectionShell(selection: $model.section)
                    .padding(.top, ST.Space.tight)
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
                     layout: .sideColumn,
                     onExport: { model.isExporting = true },
                     onOpenLibrary: { model.closeEdit() })
                .modifier(PencilScope(model: edit))
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

/// Apple Pencil selects Brush (`1g`).
///
/// Not a preference and not a mode switch: picking up the Pencil *is* the intent to paint, and
/// making the user then find a segment would be asking them to say it twice. A finger still selects
/// scopes normally, so nothing is taken away.
struct PencilScope: ViewModifier {

    var model: EditModel

    func body(content: Content) -> some View {
        #if os(iOS)
        content.onPencilSqueeze { _ in
            model.scope = .brush
        }
        #else
        content
        #endif
    }
}
