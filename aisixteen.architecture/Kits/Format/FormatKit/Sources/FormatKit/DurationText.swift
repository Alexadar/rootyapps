import Foundation

/// Durations, in the app's voice.
///
/// The rule running through all of it: a number the app has not measured is never presented as
/// one it has. `GeneratingView` shipped `Int(eta / 60).clamped(min: 1)`, which prints
/// "about 1 min left" for fifteen seconds remaining and again for eighty-nine — small lies, but
/// this whole product is an argument that a multi-minute wait can be reported honestly.
public enum DurationText {

    /// The CTA: "Redesign · ~6 min total".
    ///
    /// Before any run has been measured this uses the plan's seeded figure, and it says "about"
    /// rather than pretending to precision it does not have.
    public static func total(variations: Int, minutesEach: Double) -> String {
        let minutes = Int((Double(variations) * minutesEach).rounded())
        if minutes < 1 { return "under a minute total" }
        return "~\(minutes) min total"
    }

    /// The per-variation figure under the stepper: "about 2 min each".
    public static func each(minutes: Double) -> String {
        if minutes < 1.5 { return "about a minute each" }
        return "about \(Int(minutes.rounded())) min each"
    }

    /// Time left on the Generating screen. Nil in, nil out — the caller renders nothing, which is
    /// the honest state before three steps have been measured.
    public static func remaining(seconds: TimeInterval?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        if seconds < 45 { return "less than a minute left" }
        let minutes = Int((seconds / 60).rounded())
        if minutes <= 1 { return "about a minute left" }
        if minutes < 60 { return "about \(minutes) min left" }
        let hours = minutes / 60
        let leftover = minutes % 60
        if leftover == 0 { return hours == 1 ? "about an hour left" : "about \(hours) hours left" }
        return "about \(hours) h \(leftover) min left"
    }

    /// Appended to the current stage row: "· about 4 min left". Nil when there is nothing to say.
    public static func stageSuffix(seconds: TimeInterval?) -> String? {
        guard let text = remaining(seconds: seconds) else { return nil }
        return "· " + text
    }

    /// How long a finished render took, for the variation sidecar and the Result screen.
    public static func elapsed(seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "a moment" }
        if seconds < 60 { return "\(Int(seconds.rounded())) s" }
        let minutes = Int(seconds / 60)
        let leftover = Int(seconds.truncatingRemainder(dividingBy: 60).rounded())
        if minutes < 60 {
            return leftover == 0 ? "\(minutes) min" : "\(minutes) min \(leftover) s"
        }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}

/// Step counters. Always "step N of M" — never a percentage, and never a bare fraction.
public enum StepText {

    public static func progress(step: Int, of total: Int) -> String {
        "step \(max(step, 0)) of \(total)"
    }

    /// The Live Activity's compact trailing region, where there is room for about four characters.
    public static func compact(step: Int, of total: Int) -> String {
        "\(max(step, 0))/\(total)"
    }

    /// Shown before the first step completes. "step 0 of 32" reads like something is stuck.
    public static func starting(total: Int) -> String {
        "starting · \(total) steps"
    }
}

public enum VariationText {

    public static func count(_ number: Int) -> String {
        number == 1 ? "1 variation" : "\(number) variations"
    }

    /// The variant strip's tally: "3 of 3 done".
    public static func done(_ finished: Int, of total: Int) -> String {
        "\(finished) of \(total) done"
    }

    /// The queue note under the progress bar. Nil when nothing is queued, so the caller can drop
    /// the whole sentence rather than print "Queued next: ."
    public static func queuedNext(_ labels: [String]) -> String? {
        guard !labels.isEmpty else { return nil }
        return "Queued next: " + labels.joined(separator: ", ") + "."
    }

    /// The Live Activity's queue depth.
    public static func queueDepth(_ number: Int) -> String? {
        guard number > 0 else { return nil }
        return "\(number) queued"
    }
}
