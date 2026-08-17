import SwiftUI
import LibraryKit

/// How the grid is divided when one wallpaper leads it.
///
/// `LazyVGrid` cannot span a cell across rows, so a hero that occupies a 2×2 block cannot be a grid
/// item at all — it has to be lifted out and laid beside the two that sit next to it, with the
/// remainder falling through to the ordinary grid below.
///
/// Free and total, so the one thing that would actually hurt — an item drawn twice, or one silently
/// dropped between the two layouts — is assertable without rendering anything.
enum GalleryLayout {

    struct Split<Item>: Equatable where Item: Equatable {
        /// The 2×2 hero. `nil` when the gallery is not featuring, or has nothing to feature.
        var hero: Item?
        /// The two stacked beside it, each a single cell. Fewer when the library is nearly empty.
        var beside: [Item]
        /// Everything after, in the ordinary grid.
        var rest: [Item]
    }

    /// - Parameter columns: the grid's column count. A hero worth 2 columns needs at least 4 to
    ///   leave room beside it; below that the featured layout is refused rather than cramped, which
    ///   is why the phone's 2-column gallery is unaffected by any of this.
    static func split<Item: Equatable>(_ items: [Item], featured: Bool,
                                       columns: Int) -> Split<Item> {
        guard featured, columns >= 4, let hero = items.first else {
            return Split(hero: nil, beside: [], rest: items)
        }
        let remainder = Array(items.dropFirst())
        // The hero is two cells wide and two tall, so exactly two single cells fit alongside it.
        let beside = Array(remainder.prefix(2))
        return Split(hero: hero, beside: beside, rest: Array(remainder.dropFirst(beside.count)))
    }
}

/// Gallery — empty, grid, and the single-image view (bundle `1c`, white glass).
struct GalleryView: View {
    @Environment(\.colorScheme) private var scheme

    var library: LibraryModel
    /// Threaded through for the Enhance door in the detail sheet — see `WallpaperDetailView`.
    var create: CreateModel
    var actions: any WallpaperActions
    /// Jumps to Create with the prompt pre-filled — from the empty state and from *Use again*.
    var onUsePrompt: (String) -> Void
    var onSurpriseMe: () -> Void
    var columns: Int = 2
    var tileAspect: CGFloat = 9.0 / 19.5
    var bottomInset: CGFloat = 110
    /// Whether the most recent wallpaper leads the grid at 2×2. iPad only — see `GalleryLayout`.
    var featured: Bool = false

    @State private var selected: LibraryModel.Item?
    /// The grid's content width, for the featured row only.
    ///
    /// The 2×2 hero needs a real number: its height is two cell-heights plus a gap, and its width is
    /// two cell-widths plus a gap, so its aspect ratio changes with the container — it is not the
    /// tile ratio and cannot be expressed as one. Measured rather than nested in a `GeometryReader`,
    /// which inside a `ScrollView`'s `VStack` would claim all the height it was offered.
    @State private var gridWidth: CGFloat = 0

    var body: some View {
        Group {
            if library.isEmpty {
                EmptyGalleryView(location: library.location, onSurpriseMe: onSurpriseMe)
            } else {
                grid
            }
        }
        #if !os(macOS)
        // On the outer Group, not in the header: the header only renders in the non-empty branch,
        // so a header-only About would vanish for a brand-new user.
        .overlay(alignment: .topTrailing) {
            AboutButton(location: library.location, settings: create.settings)
                .padding(.trailing, WP.Space.margin)
                .padding(.top, WP.Space.section)
        }
        #endif
        .sheet(item: $selected) { item in
            WallpaperDetailView(item: item, library: library, create: create, actions: actions,
                                onUsePrompt: onUsePrompt)
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WP.Space.grid) {
                VStack(alignment: .leading, spacing: WP.Space.hair) {
                    Text("Gallery")
                        .wpFont(.screenTitle)
                        .foregroundStyle(WP.ink(scheme))
                    Text(library.caption)
                        .wpFont(.caption, tabularNumbers: true)
                        .foregroundStyle(WP.ink3(scheme))
                }
                .padding(.top, WP.Space.section)

                let split = GalleryLayout.split(library.items, featured: featured, columns: columns)

                if let hero = split.hero {
                    featuredRow(hero: hero, beside: split.beside)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: WP.Space.gap),
                                         count: columns),
                          spacing: WP.Space.gap) {
                    ForEach(split.rest) { item in
                        GalleryTile(item: item, library: library, aspect: tileAspect)
                            // Explicit identity so SwiftUI does not carry one tile's `@State` over
                            // to a different wallpaper when LazyVGrid recycles the view.
                            .id(item.id)
                            .onTapGesture {
                                library.requestDownload(item)
                                selected = item
                            }
                    }
                }
            }
            .padding(.horizontal, WP.Space.margin)
            .padding(.bottom, bottomInset)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
        }
    }

    /// The 2×2 hero, with the two single cells that fit beside it.
    ///
    /// Laid out from measured cell arithmetic rather than from `maxWidth: .infinity`, because an
    /// `HStack` divides space evenly and the hero must be exactly two columns and a gap — otherwise
    /// it does not line up with the ordinary grid beneath it, and the seam is the first thing the
    /// eye catches.
    @ViewBuilder
    private func featuredRow(hero: LibraryModel.Item, beside: [LibraryModel.Item]) -> some View {
        let gap = WP.Space.gap
        let cell = (gridWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)

        if cell > 0 {
            let heroWidth = cell * 2 + gap
            // Two cell-heights plus the gap between them, so the hero's bottom edge meets the second
            // side tile's — the whole point of a 2×2.
            let rowHeight = (cell / tileAspect) * 2 + gap

            HStack(alignment: .top, spacing: gap) {
                tile(hero)
                    .frame(width: heroWidth, height: rowHeight)

                VStack(spacing: gap) {
                    ForEach(beside) { item in
                        tile(item)
                            .frame(width: cell, height: (rowHeight - gap) / 2)
                    }
                    // Keeps the column top-aligned when the library holds only one or two pictures,
                    // so a nearly-empty gallery does not stretch two tiles down a hero's height.
                    if beside.count < 2 { Spacer(minLength: 0) }
                }
                .frame(width: cell, height: rowHeight, alignment: .top)
            }
        }
    }

    /// One tap target, built once — the featured row and the grid must behave identically.
    private func tile(_ item: LibraryModel.Item) -> some View {
        GalleryTile(item: item, library: library, aspect: tileAspect)
            .id(item.id)
            .onTapGesture {
                library.requestDownload(item)
                selected = item
            }
    }
}

/// One tile. No per-item metadata on the grid — the picture is the point.
struct GalleryTile: View {
    @Environment(\.colorScheme) private var scheme
    var item: LibraryModel.Item
    var library: LibraryModel
    var aspect: CGFloat

    @State private var image: PlatformImage?

    var body: some View {
        ZStack {
            if let image {
                GeometryReader { proxy in
                    Image(platformImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            } else if !item.isDownloaded {
                // A wallpaper made on another device that iCloud has not fetched yet. Real progress,
                // not a spinner — the same rule as everywhere else.
                notYetHere
            } else {
                Color.clear
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: WP.Radius.tile, style: .continuous))
        // **`clipShape` clips drawing, not hit-testing.** The `GeometryReader` inside is greedy and
        // claims more space than the tile displays, so without this each tile's tap area spills past
        // its picture. `ForEach` draws later tiles on top, so the second tile's invisible overflow
        // sat over the first tile's image — tap the first, the second gets it. Which is exactly the
        // reported symptom: every tile worked except the first.
        .contentShape(RoundedRectangle(cornerRadius: WP.Radius.tile, style: .continuous))
        .wpGlass(.regular, in: RoundedRectangle(cornerRadius: WP.Radius.tile, style: .continuous))
        // VoiceOver reads the prompt: it is the only description of the picture that exists, and it
        // is a better one than any generic "image" label.
        .accessibilityElement()
        .accessibilityLabel(item.record.prompt)
        .accessibilityAddTraits(.isButton)
        // **Clear first.** `LazyVGrid` reuses a tile's view — and with it `@State image` — when it
        // scrolls, so a recycled tile keeps displaying the previous wallpaper until the new one
        // finishes loading. That is why tapping a picture opened a different one: the sheet had the
        // right item all along, the tile was showing the wrong picture.
        .task(id: item.id) {
            image = nil
            image = await library.thumbnail(for: item)
        }
    }

    private var notYetHere: some View {
        VStack(spacing: WP.Space.tight) {
            Image(systemName: "icloud.and.arrow.down")
                .foregroundStyle(WP.ink3(scheme))
            if let fraction = item.downloadFraction {
                Text("\(Int(fraction * 100))%")
                    .wpFont(.caption, tabularNumbers: true)
                    .foregroundStyle(WP.ink3(scheme))
            }
        }
    }
}

/// The empty state, which teaches rather than apologises. It is the second thing every new user
/// sees, and *Surprise me* belongs here for the same reason it belongs on Create.
struct EmptyGalleryView: View {
    @Environment(\.colorScheme) private var scheme
    var location: StorageLocation?
    var onSurpriseMe: () -> Void

    var body: some View {
        VStack(spacing: WP.Space.margin) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.clear)
                .wpGlass(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(width: 88, height: 156)

            VStack(spacing: WP.Space.tight) {
                Text("Nothing here yet")
                    .wpFont(.cardHeading)
                    .foregroundStyle(WP.ink(scheme))
                Text(location?.emptyStatePromise
                     ?? "Wallpapers you make will gather here.")
                    .wpFont(.secondary)
                    .foregroundStyle(WP.ink2(scheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, WP.Space.section)

            Button(action: onSurpriseMe) {
                Label("Surprise me", systemImage: "sparkles")
                    .wpFont(.control)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: WP.pillHeight)
            }
            .buttonStyle(.plain)
            .wpGlassCapsule(.tinted)
        }
        .frame(maxWidth: 420)
        .padding(WP.Space.margin)
    }
}
