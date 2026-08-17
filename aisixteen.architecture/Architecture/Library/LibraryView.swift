import FormatKit
import ProjectKit
import SwiftUI

/// Library — grouped by space, variations under each.
///
/// Grouping is not decoration: it is the 4.3 argument made visible. Studio's library is a grid of
/// photographs; this one is a list of *spaces*, each with several proposals under it. A flat grid
/// of output images would be a screen that sits equally well in both apps.
///
/// The handoff shipped a hardcoded two-element array with `when: String`. Everything here is real,
/// including the two states a synced library actually has.
struct LibraryView: View {

    let library: ProjectLibrary
    let onOpen: (SpaceProject, Int) -> Void
    let onNewVariation: (SpaceProject) -> Void
    let onRename: (SpaceProject) -> Void
    let onDelete: (SpaceProject) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ARC.Space.section) {
                if library.projects.isEmpty {
                    emptyState
                } else {
                    ForEach(library.projects) { project in
                        SpaceSection(project: project,
                                     library: library,
                                     onOpen: { onOpen(project, $0) },
                                     onNewVariation: { onNewVariation(project) },
                                     onRename: { onRename(project) },
                                     onDelete: { onDelete(project) })
                    }
                }
                footer
            }
            .padding(ARC.Space.margin)
            // Manual clearance for the floating segment, which is overlaid rather than in a bar.
            .padding(.top, 64)
        }
        .background(ARC.canvasAlt)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ARC.Space.tight) {
            Text("Nothing here yet")
                .arcText(.heading)
                .foregroundStyle(ARC.ink)
            Text(library.emptyState)
                .arcText(.secondary)
                .foregroundStyle(ARC.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, ARC.Space.section)
        .accessibilityIdentifier("library.empty")
    }

    /// The storage promise, in the user's terms. Two locations, two truths, and never a word that
    /// implies an account.
    private var footer: some View {
        Text(library.caption)
            .arcText(.caption)
            .foregroundStyle(ARC.ink.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("library.caption")
    }
}

/// One space, with its variations under it.
struct SpaceSection: View {
    let project: SpaceProject
    let library: ProjectLibrary
    let onOpen: (Int) -> Void
    let onNewVariation: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: ARC.Space.gap) {
            header
            if project.isGhost {
                GhostSpaceTile(project: project) { library.requestDownload(of: project) }
            } else {
                tiles
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.space.\(project.id)")
        .contextMenu {
            Button("Rename…", action: onRename)
            Button("Use this prompt again", action: onNewVariation)
            #if os(macOS)
            Button("Reveal in Finder") {
                MacActions.reveal(project.folder)
            }
            #endif
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(project.displayName)
                .arcText(.heading)
                .foregroundStyle(ARC.ink)
                .accessibilityIdentifier("library.space.\(project.id).title")
            Spacer(minLength: ARC.Space.tight)
            Text(RelativeDayText.summary(variations: project.variations.count,
                                         date: project.createdAt,
                                         now: Date()))
                .arcText(.caption)
                .foregroundStyle(ARC.ink.opacity(0.55))
                .accessibilityIdentifier("library.space.\(project.id).count")
        }
    }

    /// The source photo, then each variation, then the add tile.
    ///
    /// At AX5 the row becomes a column: a horizontal strip of 90-point tiles beside 60-point text
    /// is a row where nothing is legible.
    @ViewBuilder private var tiles: some View {
        if typeSize >= .accessibility1 {
            VStack(spacing: ARC.Space.tight) { tileContent(height: 150) }
        } else {
            HStack(spacing: ARC.Space.tight) { tileContent(height: 110) }
        }
    }

    @ViewBuilder private func tileContent(height: CGFloat) -> some View {
        ForEach(project.variations) { variation in
            ProjectTile(project: project,
                        variation: variation,
                        library: library,
                        height: height) {
                onOpen(variation.index)
            }
        }
        AddTile(label: "New variation for \(project.displayName)",
                width: 90, height: height,
                identifier: "library.add.\(project.id)",
                action: onNewVariation)
    }
}

/// One variation's tile, in whichever of its three states it is actually in.
struct ProjectTile: View {
    let project: SpaceProject
    let variation: VariationRecord
    let library: ProjectLibrary
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if variation.imageIsPresent {
                    FileImage(url: variation.imageURL, maxPixel: 400)
                } else {
                    ghost
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: ARC.Radius.tile, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: ARC.Radius.tile))
        }
        .buttonStyle(.plain)
        .disabled(!variation.imageIsPresent)
        .accessibilityIdentifier("library.tile.\(project.id).\(variation.index)")
        .accessibilityLabel(variation.imageIsPresent
                            ? "Variation \(variation.index)"
                            : "Variation \(variation.index), not downloaded yet")
    }

    /// The sidecar arrived and the picture has not. A real percentage, never a broken image.
    private var ghost: some View {
        let state = library.downloadState(for: variation, in: project)
        return RoundedRectangle(cornerRadius: ARC.Radius.tile, style: .continuous)
            .fill(ARC.canvas)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(ARC.ink.opacity(0.4))
                    Text(StorageText.downloading(percent: state?.fraction ?? 0))
                        .arcText(.micro)
                        .foregroundStyle(ARC.ink.opacity(0.5))
                }
            }
            .onAppear { library.requestDownload(of: variation) }
    }
}

/// A whole space whose `project.json` has not arrived yet.
///
/// Shown rather than hidden: the folder is visible in Files, and pretending it is not there would
/// be the bigger lie. Nothing is fetched speculatively — the sidecar and the thumbnail are a few
/// kilobytes and are what turn this into a named tile; the full pictures wait to be asked for.
struct GhostSpaceTile: View {
    let project: SpaceProject
    let onRequest: () -> Void

    var body: some View {
        Button(action: onRequest) {
            HStack(spacing: ARC.Space.gap) {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 18))
                    .foregroundStyle(ARC.ink.opacity(0.45))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Still arriving from your other device")
                        .arcText(.secondary)
                        .foregroundStyle(ARC.ink)
                    Text("Tap to fetch it now")
                        .arcText(.micro)
                        .foregroundStyle(ARC.ink.opacity(0.5))
                }
                Spacer()
            }
            .padding(ARC.Space.grid)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: ARC.Radius.tile, style: .continuous)
                    .fill(ARC.canvas)
            }
            .contentShape(RoundedRectangle(cornerRadius: ARC.Radius.tile))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library.ghost.\(project.id)")
        .accessibilityLabel("\(project.displayName), still arriving from your other device")
        .onAppear(perform: onRequest)
    }
}
