import Foundation

/// The negative prompt — what the model is told to avoid.
///
/// ### Why a wallpaper-specific default rather than the usual one
///
/// The negative prompt everyone copies is built for character art: *bad anatomy, bad hands, missing
/// fingers, extra digit*. Those terms spend the budget on a problem this app does not have — its
/// subjects are landscapes, materials and light, and it deliberately avoids people because a face
/// in a wallpaper is a photograph and faces are where these models fail most visibly.
///
/// So the default targets what actually ruins a *wallpaper*: compression artefacts, softness,
/// blown-out or washed-out tone, and — the ones that make a generated picture look stolen rather
/// than made — watermarks, signatures and stock-image borders.
///
/// ### The 77-token limit is real and unforgiving
///
/// CLIP truncates at 77 tokens and says nothing when it does: the tail is silently dropped, so an
/// over-long negative *looks* like it is working while its last terms do nothing at all. There is no
/// long-prompt weighting here to rescue it. The default is **71 tokens**, measured with the model's
/// own tokenizer, leaving deliberate headroom.
public enum NegativePrompt {

    /// 71 tokens. Verified against `stable-diffusion-v1-5/tokenizer`.
    public static let wallpaperDefault = """
        worst quality, low quality, normal quality, lowres, jpeg artifacts, blurry, out of focus, \
        oversaturated, overexposed, washed out, watermark, signature, text, logo, username, frame, \
        border, cropped, duplicate, deformed, ugly, grainy, banding, noisy, oversharpened
        """

    /// The classic character-art negative, 47 tokens. Offered because a user who types a portrait
    /// prompt genuinely wants these, and the default deliberately omits them.
    public static let figurative = """
        lowres, bad anatomy, bad hands, text, error, missing fingers, extra digit, fewer digits, \
        cropped, worst quality, low quality, normal quality, jpeg artifacts, signature, watermark, \
        username, blurry
        """

    /// CLIP's hard limit, including the start and end markers it adds.
    public static let tokenLimit = 77

    /// A cheap upper bound on token count, for warning a user *before* their terms are silently
    /// dropped. Deliberately pessimistic: CLIP's BPE splits unusual words into several tokens, so
    /// this counts comma-separated terms plus their word count, which over-estimates rather than
    /// under-estimates. A warning that arrives late is worse than one that arrives early.
    public static func estimatedTokens(_ text: String) -> Int {
        let terms = text.split(separator: ",")
        let words = text.split(whereSeparator: { $0 == " " || $0 == "," }).count
        return words + terms.count + 2
    }

    public static func isWithinLimit(_ text: String) -> Bool {
        estimatedTokens(text) <= tokenLimit
    }
}
