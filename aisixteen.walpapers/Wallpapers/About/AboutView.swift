import SwiftUI
import GenerationKit
import LibraryKit

/// What the app is, what it is made of, and where the files are.
///
/// ### A sheet, not a third screen
///
/// The app is two screens and the switcher has no room for a third — so this is a sheet off the
/// Gallery's `⋯`. Gallery is the calm screen; Create's chrome is the one surface that must stay
/// undisturbed, because everything on it is either the prompt or the one glass object.
///
/// ### It exists because a licence obliged it
///
/// The credit was living at the bottom of Advanced, three taps deep behind a control most people
/// will never open, which is not really giving it. It has a face of its own here. The other rows
/// are the ones a support email would otherwise ask for: what model, what version, where are my
/// files.
struct AboutView: View {
    @Environment(\.colorScheme) private var scheme

    /// `nil` on Mac's standalone About window, which lives outside `RootView`'s state and resolves
    /// its own location — `LibraryLocator.resolve()` blocks on the ubiquity daemon, so it is done
    /// off the main actor.
    var location: StorageLocation?
    var settings: AdvancedSettings?

    @State private var resolvedLocation: StorageLocation?
    @State private var revealFailed = false

    private var storage: StorageLocation? { location ?? resolvedLocation }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WP.Space.section) {
                identity
                modelCard
                acknowledgementsCard
                if let settings { advancedDoorway(settings) }
                folderCard
                Text(Attribution.licenceLine)
                    .wpFont(.footnote)
                    .foregroundStyle(WP.ink3(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(WP.Space.margin)
            .frame(maxWidth: 520, alignment: .leading)
        }
        .task {
            guard location == nil, resolvedLocation == nil else { return }
            resolvedLocation = await Task.detached { LibraryLocator.resolve() }.value
        }
    }

    // MARK: Rows

    private var identity: some View {
        VStack(alignment: .leading, spacing: WP.Space.hair) {
            Text("AISixteen Wallpapers")
                .wpFont(.cardHeading)
                .foregroundStyle(WP.ink(scheme))
            Text("Version \(Bundle.main.shortVersion) · \(Attribution.onDeviceLine)")
                .wpFont(.caption)
                .foregroundStyle(WP.ink3(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modelCard: some View {
        card("Model") {
            Text(modelDescription)
                .wpFont(.caption)
                .foregroundStyle(WP.ink2(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Read from the installed pack rather than hard-coded, so a future model swap cannot leave the
    /// About sheet describing the previous one.
    private var modelDescription: String {
        guard let resources = CoreMLImageGenerator.bundledResourcesURL(),
              let model = ModelCatalog.installed(at: resources) else {
            return "No image model is installed."
        }
        var parts = ["\(model.displayName) · \(model.nativeSide) px"]
        if model.hasControlNet { parts.append("with tile refinement") }
        if Upscaler.bundledModelURL() != nil { parts.append("and an enlarger") }
        return parts.joined(separator: " ")
    }

    private var acknowledgementsCard: some View {
        card("Acknowledgements") {
            ForEach(Attribution.credits, id: \.self) { line in
                Text(line)
                    .wpFont(.caption)
                    .foregroundStyle(WP.ink2(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func advancedDoorway(_ settings: AdvancedSettings) -> some View {
        NavigationLink {
            AdvancedSettingsBody(settings: settings)
                .background(AmbientBackground(recent: nil))
                .navigationTitle("Advanced")
        } label: {
            HStack {
                Text("Advanced generation settings")
                    .wpFont(.body)
                    .foregroundStyle(WP.ink(scheme))
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WP.ink3(scheme))
            }
            .frame(minHeight: WP.minimumHitTarget)
            .padding(.horizontal, WP.Space.margin)
            .wpGlassCard()
        }
        .buttonStyle(.plain)
    }

    private var folderCard: some View {
        card("Your wallpaper folder") {
            Text(storage?.captionSuffix ?? "Resolving…")
                .wpFont(.caption)
                .foregroundStyle(WP.ink2(scheme))
            Button(revealTitle) { reveal() }
                .buttonStyle(.plain)
                .wpFont(.control)
                .foregroundStyle(WP.accent)
                .frame(minHeight: WP.minimumHitTarget, alignment: .leading)
            if revealFailed {
                // iOS has no public API for revealing a folder in Files. Rather than a button that
                // silently does nothing, the path is spelled out — the same idiom the app already
                // uses for "iOS won't let us set the wallpaper for you".
                Text("Files → \(storage?.captionSuffix ?? "On My iPhone") → AISixteen Wallpapers")
                    .wpFont(.caption)
                    .foregroundStyle(WP.ink3(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var revealTitle: String {
        #if os(macOS)
        return "Show in Finder"
        #else
        return "Open in Files"
        #endif
    }

    private func reveal() {
        guard let root = storage?.root else { revealFailed = true; return }
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([root])
        #else
        // `shareddocuments://` is the usual route and is not documented. Try it, and tell the truth
        // when it is unavailable rather than leaving a dead control.
        guard let url = URL(string: "shareddocuments://\(root.path)"),
              UIApplication.shared.canOpenURL(url) else {
            revealFailed = true
            return
        }
        UIApplication.shared.open(url)
        #endif
    }

    private func card<Content: View>(_ title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: WP.Space.tight) {
            Text(title)
                .wpFont(.control)
                .foregroundStyle(WP.ink3(scheme))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WP.Space.margin)
        .wpGlassCard()
        .accessibilityElement(children: .contain)
    }
}

#if !os(macOS)
/// The `⋯` that opens it, and its sheet.
///
/// The sheet is attached **to this button**, never to the enclosing `Group`. `GalleryView` already
/// carries a `.sheet(item:)` for the detail view, and two sheet modifiers on one view is a real
/// SwiftUI failure — the last one wins and the other silently never presents.
struct AboutButton: View {
    @Environment(\.colorScheme) private var scheme
    @State private var showing = false

    var location: StorageLocation?
    var settings: AdvancedSettings?

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(WP.ink2(scheme))
                .frame(width: WP.minimumHitTarget, height: WP.minimumHitTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About this app")
        .sheet(isPresented: $showing) {
            NavigationStack {
                AboutView(location: location, settings: settings)
                    .background(AmbientBackground(recent: nil))
                    .navigationTitle("About")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showing = false }
                        }
                    }
            }
        }
    }
}
#endif
