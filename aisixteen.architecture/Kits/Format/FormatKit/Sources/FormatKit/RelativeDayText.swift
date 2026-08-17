import Foundation

/// "today", "yesterday", "Sunday", "12 Aug".
///
/// `LibraryView` shipped these as literal `String`s in a hardcoded sample array (`when: "today"`,
/// `when: "Sunday"`), which is fine for a mockup and wrong for a library that will still be open
/// tomorrow morning.
///
/// The calendar and the reference date are both injected, so the boundary cases — midnight, a week
/// ago, a different locale — are testable without waiting for a Tuesday.
public enum RelativeDayText {

    public static func text(for date: Date,
                            now: Date,
                            calendar: Calendar = .current,
                            locale: Locale = .current) -> String {
        var calendar = calendar
        calendar.locale = locale

        // Everything is measured against the INJECTED `now`, never against the system clock.
        // `Calendar.isDateInToday` reads the real current date, which makes it untestable and,
        // worse, wrong in the one place it matters: a library rendered from a snapshot.
        let startOfDay = calendar.startOfDay(for: date)
        let startOfToday = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: startOfDay, to: startOfToday).day ?? 0

        if days == 0 { return "today" }
        if days == 1 { return "yesterday" }

        // Within the last week, the weekday name is the most useful thing a person can read: it
        // is how people actually remember when they did something.
        if days > 0 && days < 7 {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
            return formatter.string(from: date)
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        // Same year: no year. Different year: year. Nobody needs "12 Aug 2026" in August 2026.
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "d MMM" : "d MMM y")
        return formatter.string(from: date)
    }

    /// The library group's second line: "3 variations · today".
    public static func summary(variations: Int,
                               date: Date,
                               now: Date,
                               calendar: Calendar = .current,
                               locale: Locale = .current) -> String {
        VariationText.count(variations) + " · " + text(for: date, now: now, calendar: calendar, locale: locale)
    }
}

/// Storage captions. Two locations, two truths, and never a word that implies an account.
///
/// The design handoff is explicit that this app uses user-owned storage language only: iCloud is
/// the user's own folder, visible in Files. It is not a service, there is nothing to sign in to,
/// and nothing here can fail in a way that needs the word "sync".
public enum StorageText {

    public static let iCloudCaption = "In your iCloud folder — yours, in Files, on all your devices"
    public static let localCaption = "On this device — in Files, in this app's folder"

    public static let iCloudEmpty = "Spaces you redesign gather here — made on this device, kept in your iCloud."
    public static let localEmpty = "Spaces you redesign gather here — made and kept on this device."

    public static func caption(isCloud: Bool) -> String {
        isCloud ? iCloudCaption : localCaption
    }

    public static func emptyState(isCloud: Bool) -> String {
        isCloud ? iCloudEmpty : localEmpty
    }

    /// A variation that exists on another device but has not arrived yet.
    public static func downloading(percent: Double) -> String {
        let clamped = Int((min(max(percent, 0), 1) * 100).rounded())
        return clamped <= 0 ? "Not downloaded yet" : "Downloading \(clamped)%"
    }

    /// Every phrase this app must never say. Kept beside the strings it guards so the guard cannot
    /// drift away from what it is guarding.
    public static let forbiddenWords = [
        "sign in", "sign up", "log in", "account", "your account", "subscription", "subscribe",
        "credits", "upload", "server", "sync failed", "cloud service", "free trial", "upgrade to",
    ]
}
