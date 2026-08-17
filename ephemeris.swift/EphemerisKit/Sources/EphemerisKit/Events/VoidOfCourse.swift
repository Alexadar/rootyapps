import Foundation

/// The void-of-course Moon — the stretch between the Moon's last exact aspect and its change of sign.
///
/// ## The definition is a choice, and it is made here explicitly
///
/// Lilly, *Christian Astrology* (1647), the founding English horary text:
///
/// > "A planet is void of course, when he is separated from a planet, nor doth forthwith, during his
/// > being in that sign, apply to any other."
///
/// Every word of that is load-bearing, and modern practice disagrees with it in two places:
///
/// 1. **Which bodies count.** Lilly had seven planets; Uranus, Neptune and Pluto did not exist for
///    him. Including them shortens many void periods and removes some entirely. `traditional` is the
///    default because it is what the citation actually says; `modern` is offered because much
///    contemporary software uses it, and a practitioner comparing against another app needs to be
///    able to reproduce what they are seeing.
/// 2. **Applying within orb, or exact.** Lilly's "apply to" means *applying within moiety of orbs*,
///    not perfecting. This implementation uses **exact** aspects, which is what published tables and
///    virtually all software compute, and what makes a start time a single instant rather than a
///    function of whose orb table you use.
///
/// Neither choice is more correct than the other; leaving the choice implicit is what would be
/// wrong. Two apps can both be right about the void Moon and disagree by hours.
///
/// ## Why the sign matters and the aspect does not, after the fact
///
/// The period ends at the **ingress**, not at the next aspect: the Moon is void until it leaves the
/// sign it made that last aspect in, however long that takes. Periods therefore run from minutes to
/// well over a day, and a lunar month contains roughly twelve of them.
public enum VoidOfCourse {

    /// One void stretch.
    public struct Period: Identifiable, Hashable, Sendable {
        /// The instant of the Moon's last exact aspect in this sign.
        public let start: Date
        /// The instant the Moon leaves the sign — the end of the void, by definition.
        public let end: Date
        /// The sign the Moon is void in.
        public let sign: ZodiacSign
        /// The aspect that closed the sign, and to what. Nil when the Moon made no aspect at all
        /// while in this sign, which is rare but real — the whole occupancy is then void.
        public let lastAspect: AspectType?
        public let lastBody: CelestialBody?

        public var duration: TimeInterval { end.timeIntervalSince(start) }
        public var id: String { "voc-\(start.timeIntervalSince1970)" }

        public func contains(_ date: Date) -> Bool { date >= start && date < end }
    }

    /// Lilly's seven, less the Moon itself: the bodies a 17th-century astrologer could aspect.
    public static let traditional: [CelestialBody] = [.sun, .mercury, .venus, .mars, .jupiter, .saturn]
    /// The traditional set plus the three moderns, as most contemporary software counts them.
    public static let modern: [CelestialBody] = traditional + [.uranus, .neptune, .pluto]

    // MARK: - Finding the periods

    /// Every void period overlapping `interval`.
    ///
    /// Works sign occupancy by sign occupancy, because the definition is anchored to the sign: find
    /// when the Moon enters and leaves each sign, then look for its last exact aspect inside that
    /// window.
    public static func periods(in interval: DateInterval,
                               bodies: [CelestialBody] = traditional,
                               aspects: [AspectType] = AspectType.all) -> [Period] {
        // Scan a padded window and discard the outermost occupancies, because both are **clipped**
        // by the caller's interval rather than bounded by real ingresses. Building periods from
        // them produces two specific lies, and both were observed before this padding existed:
        //
        //  - the last occupancy "ends" at the window edge, so a void appears to close in the middle
        //    of a sign, at whatever moment the caller happened to ask about;
        //  - the first occupancy's aspect search starts at the window edge, so an aspect made
        //    shortly before it is invisible and the Moon looks void when it is not.
        //
        // Three days each side comfortably brackets one occupancy (~2.3 d).
        let pad = 3.0 * 86_400
        let padded = DateInterval(start: interval.start.addingTimeInterval(-pad),
                                  end: interval.end.addingTimeInterval(pad))
        let occ = occupancies(in: padded)
        guard occ.count > 2 else { return [] }

        return occ.dropFirst().dropLast().compactMap { occ -> Period? in
            let last = lastExactAspect(from: occ.start, to: occ.end, bodies: bodies, aspects: aspects)
            // With no aspect at all the Moon is void for the entire occupancy — it entered the sign
            // already having nothing left to do.
            let begins = last?.date ?? occ.start
            guard begins < occ.end else { return nil }
            return Period(start: begins, end: occ.end, sign: occ.sign,
                          lastAspect: last?.aspect, lastBody: last?.body)
        }
        // Only what the caller actually asked about — a period is relevant if any of it overlaps.
        .filter { $0.end > interval.start && $0.start < interval.end }
    }

    /// The period containing `date`, or nil when the Moon is not void.
    public static func current(at date: Date,
                               bodies: [CelestialBody] = traditional) -> Period? {
        // Three days each way comfortably brackets one sign occupancy (~2.3 days) plus its
        // neighbours, so the period containing `date` is always fully inside the window.
        let window = DateInterval(start: date.addingTimeInterval(-3 * 86_400),
                                  end: date.addingTimeInterval(3 * 86_400))
        return periods(in: window, bodies: bodies).first { $0.contains(date) }
    }

    // MARK: - Pieces

    /// When the Moon enters and leaves each sign across `interval`, clipped to it.
    static func occupancies(in interval: DateInterval) -> [(start: Date, end: Date, sign: ZodiacSign)] {
        // The Moon covers a sign in ~2.3 days and never reverses, so an hourly walk cannot skip one.
        let step = 3_600.0
        var out: [(Date, Date, ZodiacSign)] = []

        var t = interval.start
        var currentSign = ZodiacSign.from(longitude: Ephemeris.longitude(of: .moon, at: t))
        var entered = t

        while t < interval.end {
            let next = min(t.addingTimeInterval(step), interval.end)
            let sign = ZodiacSign.from(longitude: Ephemeris.longitude(of: .moon, at: next))
            if sign != currentSign {
                let boundary = refineIngress(t, next, into: sign)
                out.append((entered, boundary, currentSign))
                entered = boundary
                currentSign = sign
            }
            t = next
        }
        out.append((entered, interval.end, currentSign))
        return out.map { (start: $0.0, end: $0.1, sign: $0.2) }
    }

    /// Bisect to the instant the Moon's longitude crosses into `sign`.
    private static func refineIngress(_ lo: Date, _ hi: Date, into sign: ZodiacSign) -> Date {
        var a = lo, b = hi
        for _ in 0..<40 {
            let mid = a.addingTimeInterval(b.timeIntervalSince(a) / 2)
            let s = ZodiacSign.from(longitude: Ephemeris.longitude(of: .moon, at: mid))
            if s == sign { b = mid } else { a = mid }
        }
        return b
    }

    /// The Moon's last exact aspect strictly inside `(from, to)`.
    static func lastExactAspect(from: Date, to: Date,
                                bodies: [CelestialBody],
                                aspects: [AspectType] = AspectType.all)
    -> (date: Date, body: CelestialBody, aspect: AspectType)? {
        // Six hours: the Moon moves ~3° in that time, far less than the gap between any two aspect
        // targets, so no crossing can hide between samples.
        let step = 6 * 3_600.0
        var best: (date: Date, body: CelestialBody, aspect: AspectType)?

        for body in bodies where body != .moon {
            for asp in aspects {
                let targets: [Double] = asp.angle == 0 || asp.angle == 180
                    ? [asp.angle] : [asp.angle, -asp.angle]
                for target in targets {
                    func f(_ at: Date) -> Double {
                        AstroMath.norm180(RootFinding.signedSeparation(.moon, body, at: at) - target)
                    }
                    var t = from
                    var prev = f(t)
                    t = t.addingTimeInterval(step)
                    while t <= to {
                        let cur = f(t)
                        if RootFinding.crossesZero(prev, cur) {
                            let root = RootFinding.refine(t.addingTimeInterval(-step), t, f)
                            if root > from, root < to, best == nil || root > best!.date {
                                best = (root, body, asp)
                            }
                        }
                        prev = cur
                        t = t.addingTimeInterval(step)
                    }
                    // The tail between the last whole step and `to` still has to be searched, or an
                    // aspect perfecting in the final hours of a sign — which is the *common* case,
                    // since that is what makes a short void — would be missed entirely.
                    if t > to, t.addingTimeInterval(-step) < to {
                        let cur = f(to)
                        if RootFinding.crossesZero(prev, cur) {
                            let root = RootFinding.refine(t.addingTimeInterval(-step), to, f)
                            if root > from, root < to, best == nil || root > best!.date {
                                best = (root, body, asp)
                            }
                        }
                    }
                }
            }
        }
        return best
    }
}
