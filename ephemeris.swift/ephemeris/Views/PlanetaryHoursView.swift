import SwiftUI
import EphemerisKit

/// Where each planetary hour sits on the ring.
///
/// Pulled out of the view so the one property that must hold can be asserted without rendering:
/// **the segments are not equal**. Twelve day hours divide sunrise→sunset and twelve night hours
/// divide sunset→sunrise, and those two intervals are only the same length at the equinox. A ring
/// drawn with twenty-four equal segments is not a simplification, it is a misstatement of the
/// mathematics the whole function rests on.
enum HourRing {

    /// Start and end angle in degrees for each hour, 0° at the top, running clockwise.
    ///
    /// Proportional to real elapsed time across the whole planetary day (sunrise → next sunrise),
    /// so a summer night's twelve hours visibly occupy less of the ring than its twelve days do.
    static func angles(for hours: [PlanetaryHours.Hour]) -> [(start: Double, end: Double)] {
        guard let first = hours.first, let last = hours.last else { return [] }
        let span = last.end.timeIntervalSince(first.start)
        guard span > 0 else { return [] }

        return hours.map { hour in
            let a = hour.start.timeIntervalSince(first.start) / span
            let b = hour.end.timeIntervalSince(first.start) / span
            return (a * 360 - 90, b * 360 - 90)
        }
    }
}

/// The planetary hours as a **clock**, not a list.
///
/// The strength of this function is that it is *now*-shaped: the useful question is "which hour am
/// I in and how much of it is left", which a table answers poorly and a ring answers at a glance.
///
/// Gate 1 — needs a location, nothing else. No birth data, so it works for a user who has entered
/// only a place.
struct PlanetaryHoursView: View {
    let location: GeoLocation?
    let timeZone: TimeZone
    let now: Date

    /// Offset in hours from the current one, for tapping forward and back without leaving the ring.
    @State private var browse = 0
    @Environment(\.locale) private var locale

    private var hours: [PlanetaryHours.Hour]? {
        guard let location else { return nil }
        return PlanetaryHours.hours(startingOn: now, at: location, timeZone: timeZone)
    }

    private var currentIndex: Int? {
        hours?.firstIndex { $0.contains(now) }
    }

    private var shownIndex: Int? {
        guard let hours, let current = currentIndex else { return nil }
        return min(max(current + browse, 0), hours.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Planetary hours")
            content
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.planetaryHours")
    }

    @ViewBuilder
    private var content: some View {
        if location == nil {
            Text("Set a location to see planetary hours.")
                .font(.callout)
                .foregroundStyle(NebulaPalette.textSecondary)
                .accessibilityIdentifier("hours.noLocation")
        } else if let hours, let shown = shownIndex {
            ring(hours, shown: shown)
            detail(hours[shown], isNow: shown == currentIndex)
            stepper(hours, shown: shown)
        } else if let location {
            // ⚠️ Not an error and not an empty state to paper over — but WHICH absence matters.
            // Polar means there is no daylight interval at all; a zone mismatch means there is one
            // and the calendar being used does not contain it. Only the second is fixable by the
            // user, and only by naming it can they fix it.
            let reason = HoursUnavailable.reason(at: location, on: now, timeZone: timeZone)
            Text(reason.message)
                .font(.callout)
                .foregroundStyle(NebulaPalette.textSecondary)
                .accessibilityIdentifier(reason.identifier)
        }
    }

    // MARK: - Ring

    private func ring(_ hours: [PlanetaryHours.Hour], shown: Int) -> some View {
        let angles = HourRing.angles(for: hours)
        return ZStack {
            ForEach(Array(angles.enumerated()), id: \.offset) { i, a in
                HourSegment(startAngle: a.start, endAngle: a.end)
                    .fill(fill(for: hours[i], selected: i == shown))
                    .overlay(
                        HourSegment(startAngle: a.start, endAngle: a.end)
                            .stroke(NebulaPalette.ring.opacity(0.5), lineWidth: 0.5)
                    )
            }
            centre(hours[shown])
        }
        .frame(height: 220)
        .accessibilityIdentifier("hours.ring")
    }

    /// Day and night halves read differently, and the boundary is the only fixed point on the ring.
    private func fill(for hour: PlanetaryHours.Hour, selected: Bool) -> Color {
        if selected { return NebulaPalette.accent.opacity(0.85) }
        return hour.isDay ? NebulaPalette.accentViolet.opacity(0.30)
                          : NebulaPalette.accentCyan.opacity(0.14)
    }

    private func centre(_ hour: PlanetaryHours.Hour) -> some View {
        VStack(spacing: 2) {
            Text(hour.ruler.glyph + "\u{FE0E}")
                .font(.system(size: 34))
                .foregroundStyle(NebulaPalette.glyph)
                .nebulaGlow()
            Text(L.string(hour.ruler.name, locale: locale))
                .font(.headline)
                .accessibilityIdentifier("hours.ruler")
            Text(hour.isDay ? "Day hour \(hour.index)" : "Night hour \(hour.index - 12)")
                .font(.caption2)
                .foregroundStyle(NebulaPalette.textFaint)
                .accessibilityIdentifier("hours.index")
        }
    }

    // MARK: - Detail

    private func detail(_ hour: PlanetaryHours.Hour, isNow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(hour.start, format: .dateTime.hour().minute())
                Text(verbatim: "→")
                Text(hour.end, format: .dateTime.hour().minute())
            }
            .font(.callout).monospacedDigit()
            .accessibilityIdentifier("hours.span")

            // The length is the point: it is not sixty minutes except at the equinox.
            Text("\(Int((hour.duration / 60).rounded())) min long")
                .font(.caption)
                .foregroundStyle(NebulaPalette.textSecondary)
                .accessibilityIdentifier("hours.length")

            if isNow {
                Text("\(Int((hour.end.timeIntervalSince(now) / 60).rounded())) min remaining")
                    .font(.caption)
                    .foregroundStyle(NebulaPalette.accent)
                    .accessibilityIdentifier("hours.remaining")
            }
        }
    }

    private func stepper(_ hours: [PlanetaryHours.Hour], shown: Int) -> some View {
        HStack {
            Button { browse -= 1 } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .disabled(shown == 0)
                .accessibilityIdentifier("hours.prev")
            Spacer()
            if browse != 0 {
                Button("Now") { browse = 0 }
                    .buttonStyle(.plain)
                    .foregroundStyle(NebulaPalette.accent)
                    .accessibilityIdentifier("hours.now")
            }
            Spacer()
            Button { browse += 1 } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .disabled(shown == hours.count - 1)
                .accessibilityIdentifier("hours.next")
        }
        .font(.callout)
    }
}

/// Why there are no hours — because "there are none" has two very different causes.
///
/// `PlanetaryHours.hours` returns nil whenever it cannot bound a daylight interval, and the obvious
/// message ("no sunrise today") is **false** for the commoner of the two cases. Framing Los Angeles
/// in Kyiv's civil day gives a sunrise at 16:16 and a sunset at 05:37 — both real, but belonging to
/// different solar days, so they do not form an interval. Telling that user the Sun did not rise is
/// simply wrong, and it looks like a broken app rather than a mismatched setting they can fix.
enum HoursUnavailable {
    /// Genuinely no crossing: above the polar circles there is no daylight interval to divide.
    case polar
    /// Rise and set both exist but the chosen time zone does not frame this place's day.
    case zoneMismatch

    static func reason(at location: GeoLocation, on date: Date, timeZone: TimeZone) -> HoursUnavailable {
        let sun = RiseSet.sun(on: date, at: location, timeZone: timeZone)
        if let rise = sun.rise, let set = sun.set, set <= rise { return .zoneMismatch }
        return .polar
    }

    var message: LocalizedStringKey {
        switch self {
        case .polar:
            "The Sun does not rise or set here today, so the day cannot be divided into hours."
        case .zoneMismatch:
            "Sunrise and sunset here fall on different days in the selected time zone. Switch the zone to this place to see its hours."
        }
    }

    var identifier: String {
        switch self {
        case .polar:        "hours.noSunrise"
        case .zoneMismatch: "hours.zoneMismatch"
        }
    }
}

/// One wedge of the ring.
struct HourSegment: Shape {
    var startAngle: Double
    var endAngle: Double

    func path(in rect: CGRect) -> Path {
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.62
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: c, radius: outer,
                 startAngle: .degrees(startAngle), endAngle: .degrees(endAngle), clockwise: false)
        p.addArc(center: c, radius: inner,
                 startAngle: .degrees(endAngle), endAngle: .degrees(startAngle), clockwise: true)
        p.closeSubpath()
        return p
    }
}
