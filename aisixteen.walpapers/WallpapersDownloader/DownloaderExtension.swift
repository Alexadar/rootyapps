import BackgroundAssets
import ExtensionFoundation
import StoreKit

/// The Background Assets downloader extension.
///
/// **Not optional, and not boilerplate that can be skipped.** `AssetPackManager.shared` validates
/// the app the first time it is touched and traps outright — not an error, a `fatalError` — if the
/// app has no downloader extension. Without this target the app dies on launch on both platforms.
///
/// With Apple hosting the system does all the work: it reads the asset-pack manifest uploaded to
/// App Store Connect, decides what to fetch, and manages the transfer. The only thing this extension
/// gets to decide is *whether* a given pack should be downloaded automatically — and for an app with
/// exactly one pack, which the user explicitly consents to on the first-run gate, the answer is
/// always yes.
@main
struct DownloaderExtension: StoreDownloaderExtension {

    /// The model is the app. There is nothing to filter: the gate has already asked, and a pack
    /// declined here would leave a user who tapped *Download* watching a bar that never moves.
    func shouldDownload(_ assetPack: AssetPack) -> Bool { true }
}
