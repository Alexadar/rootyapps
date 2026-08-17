import AppIntents
import Foundation
import EphemerisKit

/// The app's content as `AppEntity` types.
///
/// ## Why these exist now, before any Siri work
///
/// Nothing here is wired to Siri yet. They are built now because they are the **substrate**: the
/// same types later carry View Annotations (`.appEntityIdentifier`, WWDC26 session 240), the
/// Spotlight semantic index, and App Intents — and SiriKit was formally deprecated at WWDC26, so
/// App Intents is where that road goes. Modelling the screen's content as entities today means the
/// Siri pass is wiring, not a rewrite.
///
/// ## What they are NOT
///
/// An entity's `@Property(title:)` is a **label**, not an explanation. `title: "Dignity"` tells a
/// model nothing about what a dignity is. That is `Glossary`'s job, and the assistant sends both.
/// Confusing the two would produce a model that knows the column headings and invents the column
/// meanings — which, next to an engine oracle-tested to arcminutes, is the worst available outcome.
///
/// ## Identifiers are stable and meaningful
///
/// Each `id` is derived from the thing itself, not from an array index. An index changes the moment
/// the window scrolls or the date moves, and an entity whose identity moves under it is one that
/// Siri will later resolve to the wrong object.

// MARK: - A body's position

struct BodyPositionEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Planet position" }
    static var defaultQuery = BodyPositionQuery()

    /// The body's own name — stable across every recomputation.
    var id: String

    @Property(title: "Body") var body: String
    @Property(title: "Sign") var sign: String
    @Property(title: "Degree in sign") var degree: String
    @Property(title: "Retrograde") var retrograde: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(body)", subtitle: "\(degree) \(sign)")
    }

    init(_ p: BodyPosition) {
        self.id = p.body.rawValue
        self.body = p.body.name
        self.sign = p.sign.name
        self.degree = p.degMinString
        self.retrograde = p.retrograde
    }
}

// MARK: - An aspect

struct AspectEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Aspect" }
    static var defaultQuery = AspectQuery()

    var id: String

    @Property(title: "Aspect") var kind: String
    @Property(title: "From") var from: String
    @Property(title: "To") var to: String
    @Property(title: "Orb") var orb: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(from) \(kind) \(to)", subtitle: "orb \(orb)")
    }

    init(_ a: DetectedAspect) {
        self.id = a.id
        self.kind = a.type.name
        self.from = a.a.name
        self.to = a.b.name
        self.orb = String(format: "%.2f°", abs(a.orb))
    }
}

// MARK: - A dated event

struct AstroEventEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Astronomical event" }
    static var defaultQuery = AstroEventQuery()

    /// The Kit's stable event `code` plus its instant: the code alone repeats every cycle.
    var id: String

    @Property(title: "Event") var label: String
    @Property(title: "Date") var date: Date
    @Property(title: "Kind") var kind: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)")
    }

    init(_ e: AstroEvent) {
        self.id = "\(e.code)-\(Int(e.date.timeIntervalSince1970))"
        self.label = e.label()
        self.date = e.date
        self.kind = e.kind.rawValue
    }
}

// MARK: - A planetary hour

struct PlanetaryHourEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Planetary hour" }
    static var defaultQuery = PlanetaryHourQuery()

    var id: String

    @Property(title: "Ruler") var ruler: String
    @Property(title: "Starts") var start: Date
    @Property(title: "Ends") var end: Date
    @Property(title: "Daytime hour") var isDay: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(ruler)", subtitle: isDay ? "day hour" : "night hour")
    }

    init(_ h: PlanetaryHours.Hour) {
        self.id = h.id
        self.ruler = h.ruler.name
        self.start = h.start
        self.end = h.end
        self.isDay = h.isDay
    }
}

// MARK: - A saved chart

struct SavedChartEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Birth chart" }
    static var defaultQuery = SavedChartQuery()

    var id: String

    @Property(title: "Name") var name: String
    @Property(title: "Born") var born: Date
    @Property(title: "Place") var place: String
    @Property(title: "Birth time known") var timeKnown: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(place)")
    }

    init(_ c: SavedChart) {
        self.id = c.id.uuidString
        self.name = c.name
        self.born = c.birthInstant
        self.place = c.placeName ?? ""
        self.timeKnown = c.isTimeKnown
    }
}

// MARK: - Query placeholder

/// `AppEntity` demands a `defaultQuery`, but nothing queries these yet — they exist to describe
/// what is on screen, not to be searched.
///
/// Returning empty is the honest placeholder. A query that guessed — "any chart whose name
/// contains…" — would be resolution logic nobody has specified, and Siri would start answering with
/// it the moment intents are added. When that pass comes, each type gets a real `EntityStringQuery`
/// written deliberately.
///
/// ⚠️ One concrete type per entity, not a generic `EmptyQuery<E>`. App Intents rejects a generic
/// query at metadata export — "all queries must have a concrete entity type" — and the failure is a
/// build error that names the export step rather than the code, so it is worth the repetition here
/// to avoid re-diagnosing it later.
struct BodyPositionQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BodyPositionEntity] { [] }
    func suggestedEntities() async throws -> [BodyPositionEntity] { [] }
}

struct AspectQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AspectEntity] { [] }
    func suggestedEntities() async throws -> [AspectEntity] { [] }
}

struct AstroEventQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AstroEventEntity] { [] }
    func suggestedEntities() async throws -> [AstroEventEntity] { [] }
}

struct PlanetaryHourQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PlanetaryHourEntity] { [] }
    func suggestedEntities() async throws -> [PlanetaryHourEntity] { [] }
}

struct SavedChartQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SavedChartEntity] { [] }
    func suggestedEntities() async throws -> [SavedChartEntity] { [] }
}
