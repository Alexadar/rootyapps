import SwiftUI
import LibraryKit

/// What "use this wallpaper" means, which is **not the same job on every platform**.
///
/// macOS can set the desktop; iOS and iPadOS cannot — there is no public API, and the best any app
/// can do is put the picture in Photos and tell the user where to go. Rather than hide that behind a
/// shared euphemism, the protocol lets each platform name its own verb and finish its own job. A
/// wallpaper app that claims to have set the wallpaper when it has not is the first one-star review.
@MainActor
protocol WallpaperActions {
    /// "Set as Desktop" on the Mac. "Save for Wallpaper" on iOS — honest, because saving is all it does.
    var primaryActionTitle: String { get }
    func performPrimary(on record: WallpaperRecord) async
    func share(_ record: WallpaperRecord)
    /// Set after `performPrimary` when the user has to finish the job themselves.
    var handoff: WallpaperHandoff? { get }
    func dismissHandoff()
}

/// The iOS handoff. Present means "the app did its part; the rest is yours."
struct WallpaperHandoff: Identifiable, Equatable {
    let id = UUID()
    var succeeded: Bool
    var message: String
}
