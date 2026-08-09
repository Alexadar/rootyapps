import Foundation

/// A composite chart: every body placed at the circular midpoint of its two source positions.
///
/// Not a chart of any moment in time — nothing was ever at these longitudes together. It is a
/// derived figure, which is why it is its own type and not a `[BodyPosition]` masquerading as a
/// real ephemeris reading.
public struct CompositeChart: Hashable {
    /// One entry per body present in *both* source charts, in the first chart's order.
    ///
    /// Each `speed` is the mean of the two source speeds — the true derivative of the midpoint,
    /// see `Composite.chart(of:and:angles:and:)` — so `retrograde` stays meaningful: a composite
    /// body reads retrograde when the pair's average motion is backwards.
    public let positions: [BodyPosition]

    /// Composite Midheaven / Ascendant: the plain midpoints of the two charts' angles, present
    /// only when both source charts supplied them.
    public let midheaven: Double?
    public let ascendant: Double?

    /// Bodies whose composite longitude fell in the opposition band and was decided by
    /// `Midpoints`' tie-break rather than by a genuinely shorter arc. Empty in ordinary charts.
    ///
    /// Surfaced rather than swallowed because a body in here could just as defensibly have been
    /// placed 180° away — the sign, the house and every aspect it makes are a coin flip, and the
    /// caller deserves to know which placements those are.
    public let ambiguousBodies: [CelestialBody]

    public func position(of body: CelestialBody) -> BodyPosition? {
        positions.first { $0.body == body }
    }

    public func longitude(of body: CelestialBody) -> Double? {
        position(of: body)?.longitude
    }
}

/// Composite charts by the **midpoint method**.
///
/// The relationship chart of two people: each body goes to the midpoint of where it stands in the
/// two natal charts. (The other family of composites — "Davison" — averages the *times and places*
/// and casts a real chart for that moment; that is a different construction and is not this.)
public enum Composite {

    /// Composite of two sets of positions, pairing bodies by identity.
    ///
    /// Bodies missing from either side are dropped rather than carried through at half strength:
    /// a midpoint needs two endpoints, and inventing the missing one would put a body somewhere no
    /// convention supports.
    ///
    /// **Speed.** The composite of `a` and `b` is `a + norm180(b − a)/2`, so away from the
    /// opposition branch its time derivative is exactly `(ȧ + ḃ)/2` — the composite body's motion
    /// is the pair's mean motion, not a re-derived ephemeris quantity. Averaging the speeds is
    /// therefore the answer, not an approximation of one.
    ///
    /// **Angles.** `midheaven` and `ascendant` are the direct midpoints of the two charts' angles.
    /// This is the honest midpoint method and it is knowingly inconsistent: the Ascendant obtained
    /// this way is generally *not* the Ascendant that belongs to the composite Midheaven at either
    /// person's latitude. Deriving one from the other would silently pick a latitude for a chart
    /// that has no place, so both angles are reported as what they are — midpoints.
    public static func chart(of a: [BodyPosition],
                             and b: [BodyPosition],
                             angles anglesA: ChartAngles? = nil,
                             and anglesB: ChartAngles? = nil) -> CompositeChart {
        var byBody: [CelestialBody: BodyPosition] = [:]
        for p in b where byBody[p.body] == nil { byBody[p.body] = p }

        var positions: [BodyPosition] = []
        var ambiguous: [CelestialBody] = []
        var seen: Set<CelestialBody> = []
        for pa in a {
            guard let pb = byBody[pa.body], seen.insert(pa.body).inserted else { continue }
            positions.append(BodyPosition(body: pa.body,
                                          longitude: Midpoints.midpoint(pa.longitude, pb.longitude),
                                          speed: (pa.speed + pb.speed) / 2))
            if Midpoints.isAmbiguous(pa.longitude, pb.longitude) { ambiguous.append(pa.body) }
        }

        let mc = anglesA.flatMap { x in anglesB.map { Midpoints.midpoint(x.midheaven, $0.midheaven) } }
        let asc = anglesA.flatMap { x in anglesB.map { Midpoints.midpoint(x.ascendant, $0.ascendant) } }
        return CompositeChart(positions: positions, midheaven: mc, ascendant: asc,
                              ambiguousBodies: ambiguous)
    }
}
