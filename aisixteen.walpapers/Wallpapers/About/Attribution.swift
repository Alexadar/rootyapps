import Foundation

/// The credit the app is contractually obliged to show, and the credit it shows because it should.
///
/// ### One of these is a licence term
///
/// The diffusion checkpoint — **Lyriel v1.6** — is distributed under CivitAI terms carrying
/// `allowNoCredit: false`. Attribution is a *condition* of redistributing those weights, and they
/// are redistributed: they sit in the app bundle. Remove the credit and the app ships outside its
/// licence.
///
/// ### The design bundle names the wrong licence
///
/// Board `6d` reads *"Images are made with Stable Diffusion 1.5 under the CreativeML Open RAIL-M
/// licence."* That is the licence of the **base model**, not of the fine-tune actually shipped.
/// Building the board as drawn would discharge an obligation the app does not have while leaving
/// the one it does have unmet. The board is right about where the credit goes and wrong about what
/// it says; this is what it says.
///
/// The authoritative record travels with the weights, in `LICENCE.txt` inside the model bundle —
/// carried there by the converter, so the terms cannot be separated from the thing they govern.
enum Attribution {

    /// Everything the pictures are made by. Listed in full even where the terms do not demand it:
    /// one honest list is easier to keep true than a list with silent omissions in it.
    static let credits: [String] = [
        "Lyriel v1.6 — the diffusion model, by its author on CivitAI.",
        "Theovercomer8's Contrast Fix — fused for deeper blacks.",
        "ControlNet 1.1 Tile by lllyasviel — used by Enhance.",
        "Real-ESRGAN by Xintao Wang and contributors — used to enlarge.",
        "Stable Diffusion 1.5, on which all of the above are built.",
    ]

    /// Shown on the About sheet's own face, not folded away behind a row. A credit the user has to
    /// go looking for is not really given.
    static let licenceLine =
        "Wallpapers are made with Lyriel v1.6, used under its CivitAI licence, which requires this credit."

    static let onDeviceLine = "Every picture is made on this device. Nothing is sent anywhere."
}
