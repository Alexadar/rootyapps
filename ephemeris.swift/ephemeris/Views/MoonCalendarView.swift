import SwiftUI
import EphemerisKit

/// The lunar month as a **grid**.
///
/// Deliberately not merged into `EventsView`. That is a chronological list for someone asking "what
/// is coming up"; this is a calendar for someone asking "what is the Moon doing *this month*". Same
/// data, different question, and the docs call out merging them as the wrong move — a timeline
/// cannot answer "which weekend is nearest the full moon" at a glance, which is most of why people
/// buy a moon calendar at all.
///
/// Gate 0 for the grid itself: phase and illumination need only the clock. **Rise and set need a
/// location**, so they appear in the day detail and honestly say so when there is none.
struct MoonCalendarView: View {
    let location: GeoLocation?
    let timeZone: TimeZone
    /// The app's current instant, so the calendar opens on the month the rest of the app is showing.
    let now: Date

    @State private var monthAnchor: Date?
    @State private var selected: Date?
    /// Off by default and deliberately so: void-of-course is a horary practitioner's tool and means
    /// nothing to the larger audience a moon calendar is for. Opting in is a Settings decision.
    @AppStorage("moon.voidOfCourse") private var showVoid = false
    @Environment(\.locale) private var locale

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = locale
        return c
    }

    private var anchor: Date { monthAnchor ?? now }
    /// Latitude only steers which way the crescent points; with no location the northern default is
    /// as good as any and the disc is still the right *shape*.
    private var latitude: Double { location?.latitude ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            weekdayRow
            grid
            if let selected { detail(for: selected) }
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.moonCalendar")
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("moon.prevMonth")
            Spacer()
            Text(anchor, format: .dateTime.month(.wide).year())
                .font(.headline)
                .accessibilityIdentifier("moon.monthTitle")
            Spacer()
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("moon.nextMonth")
        }
    }

    private func step(_ months: Int) {
        monthAnchor = calendar.date(byAdding: .month, value: months, to: anchor)
        selected = nil
    }

    // MARK: - Grid

    /// Locale-correct weekday order: a German week starts on Monday, an American one on Sunday.
    /// Hardcoding Sunday-first would misalign every column for most of Europe.
    private var weekdaySymbols: [String] {
        let s = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(s[first...] + s[..<first])
    }

    private var weekdayRow: some View {
        HStack(spacing: 2) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(verbatim: symbol)
                    .font(.caption2)
                    .foregroundStyle(NebulaPalette.textFaint)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Days of the displayed month, padded at the front so the first lands under its weekday.
    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: anchor),
              let count = calendar.range(of: .day, in: .month, for: anchor)?.count
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = (0..<count).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
        return Array(repeating: nil, count: leading) + days.map { Optional($0) }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day { cell(day) } else { Color.clear.frame(height: 44) }
            }
        }
    }

    private func cell(_ day: Date) -> some View {
        // Noon, not midnight: the disc should describe the day as a whole, and midnight sits at the
        // boundary where a phase label can flip to the neighbouring day.
        let sample = calendar.date(byAdding: .hour, value: 12,
                                   to: calendar.startOfDay(for: day)) ?? day
        let snapshot = MoonPhases.snapshot(at: sample)
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let isSelected = selected.map { calendar.isDate(day, inSameDayAs: $0) } ?? false

        return VStack(spacing: 3) {
            Text(day, format: .dateTime.day())
                .font(.caption2)
                .foregroundStyle(isToday ? NebulaPalette.accent : NebulaPalette.textSecondary)
            MoonDiscView(illumination: snapshot.illumination,
                         waxing: snapshot.waxing,
                         latitude: latitude,
                         size: 16)
            // A principal phase falling on this day earns a dot; the grid is otherwise a smooth
            // gradient and the four instants that matter would be invisible in it.
            Circle()
                .fill(principalPhase(on: day) != nil ? NebulaPalette.accent : .clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(isSelected ? NebulaPalette.cardFillAlt : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onTapGesture { selected = day }
        .accessibilityIdentifier("moon.day.\(calendar.component(.day, from: day))")
    }

    /// Whether one of the four principal phases falls on this civil day.
    private func principalPhase(on day: Date) -> MoonPhases.Phase? {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return MoonPhases.phases(in: DateInterval(start: start, end: end)).first?.phase
    }

    // MARK: - Day detail

    private func detail(for day: Date) -> some View {
        let sample = calendar.date(byAdding: .hour, value: 12,
                                   to: calendar.startOfDay(for: day)) ?? day
        let snapshot = MoonPhases.snapshot(at: sample)
        let rs = location.map { MoonPhases.riseSet(on: day, at: $0, timeZone: timeZone) }

        return VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(NebulaPalette.divider)
            HStack(spacing: 10) {
                MoonDiscView(illumination: snapshot.illumination,
                             waxing: snapshot.waxing,
                             latitude: latitude,
                             size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.subheadline)
                        .accessibilityIdentifier("moon.detail.date")
                    // Percent sign inside the value, so the catalog key stays "%@ illuminated"
                    // and matches the one the widget already ships in sixteen languages.
                    Text("\("\(snapshot.percent)%") illuminated")
                        .font(.caption)
                        .foregroundStyle(NebulaPalette.textSecondary)
                        .accessibilityIdentifier("moon.detail.illumination")
                }
                Spacer()
            }
            riseSetLine(rs)
            if showVoid { voidLine(for: day) }
        }
    }

    /// Void-of-course stretches touching this day.
    ///
    /// The Kit defaults to Lilly's traditional seven; the period shown here is therefore the
    /// traditional reading, and a practitioner comparing against software that counts the outers
    /// will see a later start. That is a real disagreement between two defensible definitions, not
    /// a defect, which is why the body set is named on screen rather than left implicit.
    @ViewBuilder
    private func voidLine(for day: Date) -> some View {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let periods = VoidOfCourse.periods(in: DateInterval(start: start, end: end))

        VStack(alignment: .leading, spacing: 2) {
            Text("Void of course").font(.caption2).foregroundStyle(NebulaPalette.textFaint)
            if periods.isEmpty {
                Text("None today").font(.caption)
                    .foregroundStyle(NebulaPalette.textSecondary)
                    .accessibilityIdentifier("moon.detail.voidNone")
            } else {
                ForEach(periods) { p in
                    HStack(spacing: 6) {
                        Text(p.start, format: .dateTime.hour().minute())
                        Text(verbatim: "→")
                        Text(p.end, format: .dateTime.hour().minute())
                        if let b = p.lastBody {
                            Text(verbatim: "· \(b.glyph)\u{FE0E}")
                                .foregroundStyle(NebulaPalette.textFaint)
                        }
                    }
                    .font(.caption).monospacedDigit()
                    .accessibilityIdentifier("moon.detail.void")
                }
            }
        }
    }

    /// ⚠️ Absence is a real answer here and is printed as one.
    ///
    /// The Moon fails to rise or set on about one day a month at **every** latitude, because its day
    /// runs ~50 minutes longer than the solar one — this is not a polar edge case, and inside the
    /// Arctic Circle it can persist for days. `RiseSet` returns nil for exactly those days and this
    /// view says so. Substituting the neighbouring day's time would be a plausible-looking lie.
    @ViewBuilder
    private func riseSetLine(_ rs: (rise: Date?, set: Date?)?) -> some View {
        if let rs {
            HStack(spacing: 14) {
                label("Moonrise", rs.rise, id: "moon.detail.rise")
                label("Moonset", rs.set, id: "moon.detail.set")
            }
        } else {
            Text("Set a location to see moonrise and moonset.")
                .font(.caption)
                .foregroundStyle(NebulaPalette.textFaint)
                .accessibilityIdentifier("moon.detail.noLocation")
        }
    }

    private func label(_ title: LocalizedStringKey, _ date: Date?, id: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(NebulaPalette.textFaint)
            if let date {
                Text(date, format: .dateTime.hour().minute())
                    .font(.caption).monospacedDigit()
                    .accessibilityIdentifier(id)
            } else {
                Text("Does not occur today")
                    .font(.caption)
                    .foregroundStyle(NebulaPalette.textSecondary)
                    .accessibilityIdentifier("\(id).absent")
            }
        }
    }
}
