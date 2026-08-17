import Foundation
import Testing
@testable import FormatKit

@Suite("Durations")
struct DurationTextChecks {

    @Test("The CTA prices the whole job in minutes")
    func ctaTotal() {
        #expect(DurationText.total(variations: 3, minutesEach: 2) == "~6 min total")
        #expect(DurationText.total(variations: 1, minutesEach: 2) == "~2 min total")
        #expect(DurationText.total(variations: 5, minutesEach: 2.4) == "~12 min total")
    }

    @Test("Fifteen seconds never reads as a minute")
    func shortDurationsAreHonest() {
        // `GeneratingView` shipped `Int(eta / 60).clamped(min: 1)`, which prints "about 1 min left"
        // for fifteen seconds and again for eighty-nine.
        #expect(DurationText.remaining(seconds: 15) == "less than a minute left")
        #expect(DurationText.remaining(seconds: 44) == "less than a minute left")
        #expect(DurationText.remaining(seconds: 45) == "about a minute left")
        #expect(DurationText.remaining(seconds: 89) == "about a minute left")
        #expect(DurationText.remaining(seconds: 100) == "about 2 min left")
    }

    @Test("No measurement produces no words, never a zero")
    func nilInNilOut() {
        #expect(DurationText.remaining(seconds: nil) == nil)
        #expect(DurationText.stageSuffix(seconds: nil) == nil)
        // Not a number, not "0 min left", not "calculating…".
        #expect(DurationText.remaining(seconds: .nan) == nil)
        #expect(DurationText.remaining(seconds: .infinity) == nil)
        #expect(DurationText.remaining(seconds: -5) == nil)
    }

    @Test("Long durations read as sentences, not as clock arithmetic")
    func longDurations() {
        #expect(DurationText.remaining(seconds: 59 * 60) == "about 59 min left")
        #expect(DurationText.remaining(seconds: 3600) == "about an hour left")
        #expect(DurationText.remaining(seconds: 7200) == "about 2 hours left")
        #expect(DurationText.remaining(seconds: 95 * 60) == "about 1 h 35 min left")
    }

    @Test("The stage suffix carries its separator, or nothing at all")
    func stageSuffix() {
        #expect(DurationText.stageSuffix(seconds: 240) == "· about 4 min left")
    }

    @Test("Per-variation copy avoids the bare number one")
    func eachReadsWell() {
        #expect(DurationText.each(minutes: 1) == "about a minute each")
        #expect(DurationText.each(minutes: 2) == "about 2 min each")
        #expect(DurationText.each(minutes: 2.4) == "about 2 min each")
    }

    @Test("Elapsed time is exact, because it actually happened")
    func elapsedIsExact() {
        // Time left is an estimate and hedges. Time taken is a fact and does not.
        #expect(DurationText.elapsed(seconds: 45) == "45 s")
        #expect(DurationText.elapsed(seconds: 120) == "2 min")
        #expect(DurationText.elapsed(seconds: 135) == "2 min 15 s")
        #expect(DurationText.elapsed(seconds: 3900) == "1 h 5 min")
        #expect(DurationText.elapsed(seconds: 0) == "a moment")
    }
}

@Suite("Steps and variations")
struct CounterTextChecks {

    @Test("Progress is always steps, never a percentage")
    func stepsNotPercent() {
        // Step-based, never a 0–1 float — the rule that runs from the seam to the screen.
        #expect(StepText.progress(step: 18, of: 32) == "step 18 of 32")
        #expect(StepText.compact(step: 18, of: 32) == "18/32")
        #expect(!StepText.progress(step: 18, of: 32).contains("%"))
    }

    @Test("Before the first step it says starting, not step zero")
    func zeroReadsAsStarting() {
        // "step 0 of 32" reads like something is stuck.
        #expect(StepText.starting(total: 32) == "starting · 32 steps")
        #expect(StepText.progress(step: -1, of: 32) == "step 0 of 32")
    }

    @Test("One variation is singular")
    func singularVariation() {
        #expect(VariationText.count(1) == "1 variation")
        #expect(VariationText.count(3) == "3 variations")
        #expect(VariationText.count(0) == "0 variations")
    }

    @Test("The variant tally matches the design board")
    func doneTally() {
        #expect(VariationText.done(3, of: 3) == "3 of 3 done")
        #expect(VariationText.done(1, of: 3) == "1 of 3 done")
    }

    @Test("An empty queue produces no sentence at all")
    func emptyQueueIsSilent() {
        // Otherwise the leave-note reads "Queued next: ."
        #expect(VariationText.queuedNext([]) == nil)
        #expect(VariationText.queueDepth(0) == nil)
        #expect(VariationText.queuedNext(["Variation 2", "Variation 3"])
                == "Queued next: Variation 2, Variation 3.")
        #expect(VariationText.queueDepth(2) == "2 queued")
    }
}

@Suite("Relative days")
struct RelativeDayChecks {

    // A fixed clock and a pinned locale: a suite that depends on what day it is today is a suite
    // that fails on a Tuesday.
    let locale = Locale(identifier: "en_US")
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    /// Wednesday, 12 August 2026, 14:22 UTC.
    let now = Date(timeIntervalSince1970: 1_786_544_520)

    private func day(_ offset: Int, hour: Int = 10) -> Date {
        calendar.date(byAdding: .day, value: -offset,
                      to: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)!)!
    }

    @Test("Today and yesterday are named")
    func todayAndYesterday() {
        #expect(RelativeDayText.text(for: day(0), now: now, calendar: calendar, locale: locale) == "today")
        #expect(RelativeDayText.text(for: day(1), now: now, calendar: calendar, locale: locale) == "yesterday")
    }

    @Test("Within the last week, the weekday name is what people remember")
    func recentDaysUseWeekdayNames() {
        // 12 Aug 2026 is a Wednesday.
        #expect(RelativeDayText.text(for: day(2), now: now, calendar: calendar, locale: locale) == "Monday")
        #expect(RelativeDayText.text(for: day(3), now: now, calendar: calendar, locale: locale) == "Sunday")
        #expect(RelativeDayText.text(for: day(6), now: now, calendar: calendar, locale: locale) == "Thursday")
    }

    @Test("Beyond a week it becomes a date, with no year inside the same year")
    func olderDaysUseDates() {
        let text = RelativeDayText.text(for: day(30), now: now, calendar: calendar, locale: locale)
        #expect(text.contains("Jul"))
        #expect(!text.contains("2026"), "nobody needs the year in the year it already is")
    }

    @Test("A different year carries its year")
    func differentYearShowsIt() {
        let text = RelativeDayText.text(for: day(400), now: now, calendar: calendar, locale: locale)
        #expect(text.contains("2025"))
    }

    @Test("Just after midnight is still today")
    func midnightBoundary() {
        // A render finished at 00:05 must not read "yesterday" at 00:10.
        let justAfterMidnight = calendar.date(bySettingHour: 0, minute: 5, second: 0, of: now)!
        #expect(RelativeDayText.text(for: justAfterMidnight, now: now, calendar: calendar, locale: locale) == "today")
    }

    @Test("The library group's second line joins count and day")
    func summaryLine() {
        #expect(RelativeDayText.summary(variations: 3, date: day(0), now: now,
                                        calendar: calendar, locale: locale) == "3 variations · today")
        #expect(RelativeDayText.summary(variations: 2, date: day(3), now: now,
                                        calendar: calendar, locale: locale) == "2 variations · Sunday")
    }
}

@Suite("Storage language is user-owned")
struct StorageTextChecks {

    @Test("iCloud and local tell two different truths")
    func captionsDiffer() {
        #expect(StorageText.caption(isCloud: true) != StorageText.caption(isCloud: false))
        #expect(StorageText.emptyState(isCloud: true) != StorageText.emptyState(isCloud: false))
        #expect(StorageText.caption(isCloud: true).contains("iCloud"))
        #expect(StorageText.caption(isCloud: false).contains("this device"))
        // Both promise Files, because both are true.
        #expect(StorageText.caption(isCloud: true).contains("Files"))
        #expect(StorageText.caption(isCloud: false).contains("Files"))
    }

    @Test("No storage string implies an account or a service")
    func nothingImpliesAnAccount() {
        // iCloud is the user's own folder. There is nothing to sign in to and nothing that can be
        // taken away, and the copy has to keep being true about that.
        let strings = [StorageText.iCloudCaption, StorageText.localCaption,
                       StorageText.iCloudEmpty, StorageText.localEmpty,
                       StorageText.downloading(percent: 0.4)]
        for string in strings {
            let lowered = string.lowercased()
            for word in StorageText.forbiddenWords {
                #expect(!lowered.contains(word), "\"\(string)\" contains \"\(word)\"")
            }
        }
    }

    @Test("Download progress reads as a real percentage, both ends included")
    func downloadPercent() {
        #expect(StorageText.downloading(percent: 0) == "Not downloaded yet")
        #expect(StorageText.downloading(percent: 0.42) == "Downloading 42%")
        #expect(StorageText.downloading(percent: 1) == "Downloading 100%")
        #expect(StorageText.downloading(percent: 5) == "Downloading 100%")
        #expect(StorageText.downloading(percent: -1) == "Not downloaded yet")
    }
}
