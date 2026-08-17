import Foundation

/// Words that appear in more than one place, kept in one.
///
/// Enhance is reachable from the Create result and from the Gallery detail sheet, and the design
/// calls for *one treatment, both doors*. Copy that is retyped at each door drifts — one says "about
/// a minute" and the other says nothing, and neither is wrong enough for anyone to notice.
enum EnhanceCopy {

    /// Stated **before** the tap, because it is a minute of the user's phone doing nothing else.
    /// Measured at ~42 s on this Mac for nine tiles; longer on a phone, so "about a minute" is the
    /// honest round rather than the flattering one.
    static let cost = "Enhance redraws fine detail · about a minute"

    /// Why Create just refused. Raised as a toast rather than shown as a disabled tooltip: the
    /// button has to stay tappable to say anything at all.
    static let oneThingAtATime = "One thing at a time — this finishes in a few tiles."

    /// Appended to the failure card when an Enhance fails. The wallpaper is only overwritten once,
    /// at the very end, so a refinement that dies part-way genuinely has not touched it — and the
    /// user's first fear is that it has.
    static let untouched = "Your wallpaper is untouched."
}
