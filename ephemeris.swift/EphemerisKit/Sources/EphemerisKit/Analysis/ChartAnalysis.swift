import Foundation

// MARK: - Triplicity / quadruplicity

/// The four classical triplicities (elements).
///
/// Declaration order is load-bearing: the tropical signs cycle fire → earth → air → water
/// starting at Aries, so `Element.allCases[sign.rawValue % 4]` *is* the assignment table.
public enum Element: String, CaseIterable, Hashable, Sendable {
    case fire, earth, air, water
}

/// The three classical quadruplicities (modalities).
///
/// Same trick as `Element`: the signs cycle cardinal → fixed → mutable from Aries,
/// so the modality is `rawValue % 3` and no lookup table can drift out of sync.
public enum Modality: String, CaseIterable, Hashable, Sendable {
    case cardinal, fixed, mutable
}

extension ZodiacSign {
    public var element: Element { Element.allCases[rawValue % 4] }
    public var modality: Modality { Modality.allCases[rawValue % 3] }
}

/// A count per case of a small closed enumeration.
///
/// Every case is materialised with an explicit zero, so `total` is always the number of bodies
/// counted — a caller can never mistake "absent key" for "zero bodies", and the sum invariant
/// is checkable rather than accidental.
public struct Balance<Key: Hashable & CaseIterable & Sendable>: Hashable, Sendable {
    public let counts: [Key: Int]

    public init(counting keys: [Key]) {
        var c: [Key: Int] = [:]
        for k in Key.allCases { c[k] = 0 }
        for k in keys { c[k, default: 0] += 1 }
        counts = c
    }

    public subscript(key: Key) -> Int { counts[key] ?? 0 }

    public var total: Int { counts.values.reduce(0, +) }

    /// Cases in declaration order with their counts — the order a UI should render.
    public var ordered: [(key: Key, count: Int)] { Key.allCases.map { ($0, self[$0]) } }

    /// The single most-tenanted case, or `nil` when the maximum is shared. A tie is a real
    /// result here ("balanced"), not something to break arbitrarily.
    public var strongest: Key? {
        let ranked = ordered.sorted { $0.count > $1.count }
        guard let top = ranked.first, top.count > 0 else { return nil }
        guard ranked.count == 1 || ranked[1].count < top.count else { return nil }
        return top.key
    }

    /// Cases with no bodies at all.
    public var missing: [Key] { ordered.filter { $0.count == 0 }.map(\.key) }
}

// MARK: - Chart pattern

/// The seven planetary patterns of Marc Edmund Jones.
///
/// Declaration order is the order Jones presents them and is relied on by the oracle corpus
/// (patterns are compared by their index in `allCases`); do not reorder without updating it.
public enum ChartPattern: String, CaseIterable, Hashable, Sendable {
    case bundle, bowl, bucket, locomotive, seesaw, splash, splay
}

/// One run of bodies uninterrupted by an empty sextile, in ascending cyclic longitude.
public struct ChartCluster: Hashable, Sendable {
    /// Indices into the longitude array handed to the classifier, in cyclic order.
    public let indices: [Int]
    /// Longitude of the first body of the run, degrees [0, 360).
    public let start: Double
    /// Degrees from the first body of the run to the last, always in [0, 360).
    public let span: Double

    public var count: Int { indices.count }
}

/// The measured geometry a `ChartPattern` is decided from.
///
/// ### Rule
///
/// Jones (*The Guide to Horoscope Interpretation*, 1941) names the seven patterns but describes
/// them in prose; the numeric thresholds below are the ones Robert Jansky and Bil Tierney made
/// explicit and which every implementation since has used:
///
/// * an **empty sextile** (a gap ≥ 60°) is what divides one group of bodies from another;
/// * an **empty trine** (≥ 120°) is the locomotive's signature;
/// * a **hemisphere** (≥ 180°) is the bowl's;
/// * everything inside a **trine** (span ≤ 120°) is a bundle.
///
/// Sort the longitudes, take the cyclic gaps (they sum to 360°), let `g₁` be the largest and
/// `L` the number of gaps ≥ 60°. `occupiedSpan = 360 − g₁`. Then, in this order:
///
/// 1. `occupiedSpan ≤ 120°` → **bundle**. Checked first, so a bundle that happens to contain
///    one wide internal gap is still a bundle — the total spread is the defining fact.
/// 2. `L == 2` and the smaller group is point-like (≤ 2 bodies inside 8°, the conjunction orb)
///    → **bucket**, that group being the handle. Checked before bowl, because a bowl with a
///    lone planet dropped in the empty half still has `g₁ ≥ 180°` and would otherwise be
///    misread as a bowl. Two gaps ≥ 60° is exactly Jansky's requirement that the handle stand
///    clear of *both* rims of the bowl.
/// 3. `L == 1`, `g₁ ≥ 180°` → **bowl** (everything in one hemisphere).
/// 4. `L == 1`, `g₁ ≥ 120°` → **locomotive** (an empty trine, bodies over two thirds).
/// 5. `L == 2` → **seesaw** (two groups, each with real width, standing apart).
/// 6. `L ≤ 1`, `g₁ < 120°` → **splash** (nothing large enough to group by).
/// 7. otherwise (`L ≥ 3`, three or more groups) → **splay**.
///
/// Boundaries are inclusive at the lower end (a gap of exactly 120° is a locomotive, a span of
/// exactly 120° is a bundle), which is the usual convention and keeps the cases exhaustive.
///
/// All arithmetic is on cyclic gaps, so the classification is invariant under rotation of the
/// whole chart — including across the 0°/360° seam. That invariance is asserted in the tests;
/// it is the property this file exists to protect.
public struct ChartShape: Hashable, Sendable {
    public let pattern: ChartPattern
    /// Arc actually occupied, `360 − largestGap`, degrees.
    public let occupiedSpan: Double
    public let largestGap: Double
    public let secondLargestGap: Double
    /// Groups separated by empty sextiles, in cyclic order starting after the first such gap.
    public let clusters: [ChartCluster]
    /// The handle group of a `.bucket`; `nil` for every other pattern.
    public let handle: ChartCluster?

    /// A gap this wide or wider separates two groups (an empty sextile).
    public static let groupingGap = 60.0
    /// A gap this wide or wider is an empty trine — the locomotive's signature.
    public static let emptyTrine = 120.0
    /// A span this wide or narrower is a bundle (bodies inside one trine).
    public static let bundleSpan = 120.0
    /// A group no wider than this reads as a single point — the conjunction orb of `AspectType`.
    public static let handleSpan = 8.0
    /// A group of at most this many bodies may serve as a bucket handle (a tight conjunction).
    public static let handleMaxBodies = 2

    /// Classify a set of ecliptic longitudes. `nil` for fewer than three bodies, where the
    /// patterns are not defined (two points always look like a seesaw or a bundle).
    public static func classify(longitudes: [Double]) -> ChartShape? {
        let n = longitudes.count
        guard n >= 3 else { return nil }

        let lons = longitudes.map(AstroMath.norm360)
        let order = (0..<n).sorted { lons[$0] == lons[$1] ? $0 < $1 : lons[$0] < lons[$1] }
        let sorted = order.map { lons[$0] }

        // Gap AFTER each body, cyclically. These sum to 360° for any set that is not a single
        // point; the all-identical case degenerates to all zeros and is handled first.
        let gaps = (0..<n).map { AstroMath.norm360(sorted[($0 + 1) % n] - sorted[$0]) }
        let ranked = gaps.sorted(by: >)
        let g1 = ranked[0]
        let g2 = ranked.count > 1 ? ranked[1] : 0

        guard g1 > 0 else {                       // every body on the same degree
            let cluster = ChartCluster(indices: order, start: sorted[0], span: 0)
            return ChartShape(pattern: .bundle, occupiedSpan: 0, largestGap: 360,
                              secondLargestGap: 0, clusters: [cluster], handle: nil)
        }

        let occupiedSpan = 360 - g1
        let clusters = group(order: order, sorted: sorted, gaps: gaps)
        let big = gaps.filter { $0 >= groupingGap }.count

        // Handle candidate: strictly the smaller group, point-like, with a real group opposite.
        var handle: ChartCluster? = nil
        if big == 2, clusters.count == 2 {
            let a = clusters[0], b = clusters[1]
            if a.count != b.count {
                let small = a.count < b.count ? a : b
                if small.count <= handleMaxBodies && small.span <= handleSpan {
                    handle = small
                }
            }
        }

        let pattern: ChartPattern
        if occupiedSpan <= bundleSpan {
            pattern = .bundle
        } else if handle != nil {
            pattern = .bucket
        } else if big == 1 && g1 >= 180 {
            pattern = .bowl
        } else if big == 1 && g1 >= emptyTrine {
            pattern = .locomotive
        } else if big == 2 {
            pattern = .seesaw
        } else if big <= 1 {
            pattern = .splash
        } else {
            pattern = .splay
        }

        return ChartShape(pattern: pattern, occupiedSpan: occupiedSpan,
                          largestGap: g1, secondLargestGap: g2,
                          clusters: clusters, handle: pattern == .bucket ? handle : nil)
    }

    /// Cut the sorted ring at every empty sextile. With no such gap the whole ring is one
    /// cluster; with exactly one it is still one cluster, but one that wraps the seam — which
    /// is why this walks the ring modulo `n` instead of slicing an array.
    private static func group(order: [Int], sorted: [Double], gaps: [Double]) -> [ChartCluster] {
        let n = order.count
        let breaks = (0..<n).filter { gaps[$0] >= groupingGap }
        guard !breaks.isEmpty else {
            return [ChartCluster(indices: order, start: sorted[0],
                                 span: AstroMath.norm360(sorted[n - 1] - sorted[0]))]
        }
        var out: [ChartCluster] = []
        for (k, p) in breaks.enumerated() {
            let q = breaks[(k + 1) % breaks.count]
            var indices: [Int] = []
            var i = (p + 1) % n
            while true {
                indices.append(order[i])
                if i == q { break }
                i = (i + 1) % n
            }
            let first = sorted[(p + 1) % n], last = sorted[q]
            out.append(ChartCluster(indices: indices, start: first,
                                    span: AstroMath.norm360(last - first)))
        }
        return out
    }
}

// MARK: - Aspect weight

/// How strongly one body is tied into the rest of the chart.
public struct BodyScore: Hashable {
    public let body: CelestialBody
    public let aspectCount: Int
    /// Sum over the body's aspects of `1 − orb / maxOrb`: an exact aspect contributes 1, one at
    /// the edge of orb contributes 0. All five Ptolemaic types count the same — weighting them
    /// against each other would be an interpretive claim, and this file makes none.
    public let score: Double
}

// MARK: - Chart analysis

/// Computed structure of a chart: elemental and modal balance, aspect weight per body,
/// unaspected bodies, and the Jones pattern. Numbers and classifications only — no meaning.
public struct ChartAnalysis: Hashable {
    /// How many bodies were considered; both balances sum to exactly this.
    public let bodyCount: Int
    public let elements: Balance<Element>
    public let modalities: Balance<Modality>
    /// Every body considered, most tied-in first. Ties break on aspect count, then on
    /// `CelestialBody.allCases` order, so the ranking is total and reproducible.
    public let scores: [BodyScore]
    /// Bodies making no Ptolemaic aspect at all at the orb factor used.
    public let unaspected: [CelestialBody]
    public let shape: ChartShape?

    public var pattern: ChartPattern? { shape?.pattern }

    /// Highest aspect weight. `nil` only for an empty chart; note it is *not* required to be a
    /// strict maximum — see `scores` for the tie-break.
    public var dominant: CelestialBody? { scores.first?.body }

    /// The bodies forming a bucket's handle; empty for every other pattern.
    public var handleBodies: [CelestialBody] { shape?.handle?.indices.map { bodies[$0] } ?? [] }

    private let bodies: [CelestialBody]

    /// - Parameter orbFactor: multiplies each aspect type's base orb, matching `Aspects.detect`.
    public init(positions: [BodyPosition], orbFactor: Double = 1) {
        let signs = positions.map { ZodiacSign.from(longitude: $0.longitude) }
        bodyCount = positions.count
        bodies = positions.map(\.body)
        elements = Balance(counting: signs.map(\.element))
        modalities = Balance(counting: signs.map(\.modality))
        shape = ChartShape.classify(longitudes: positions.map(\.longitude))

        let aspects = Aspects.detect(in: positions, orbFactor: orbFactor)
        var count: [CelestialBody: Int] = [:]
        var weight: [CelestialBody: Double] = [:]
        for a in aspects {
            let maxOrb = a.type.baseOrb * orbFactor
            let w = maxOrb > 0 ? max(0, 1 - a.orb / maxOrb) : 1
            for body in [a.a, a.b] {
                count[body, default: 0] += 1
                weight[body, default: 0] += w
            }
        }
        let rank = Dictionary(uniqueKeysWithValues: CelestialBody.allCases.enumerated()
            .map { ($0.element, $0.offset) })
        scores = positions.map {
            BodyScore(body: $0.body,
                      aspectCount: count[$0.body] ?? 0,
                      score: weight[$0.body] ?? 0)
        }.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.aspectCount != $1.aspectCount { return $0.aspectCount > $1.aspectCount }
            return (rank[$0.body] ?? 0) < (rank[$1.body] ?? 0)
        }
        unaspected = positions.map(\.body).filter { (count[$0] ?? 0) == 0 }
    }
}
