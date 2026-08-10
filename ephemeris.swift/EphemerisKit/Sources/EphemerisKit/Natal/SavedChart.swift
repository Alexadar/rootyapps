import Foundation

/// A saved birth chart.
///
/// ## Why these fields exist, and why now
///
/// Four of them are not for the UI at all — `id`, `schemaVersion`, `modifiedAt` and `deletedAt` are
/// what make the store *syncable later without a migration*. Adding sync afterwards to records that
/// lack a stable identity and a modification time means merging libraries that have already diverged
/// across a user's devices, which is materially harder than carrying four fields from the start.
///
/// `deletedAt` is a tombstone rather than an actual removal for the same reason: a device that was
/// offline when a chart was deleted would otherwise resurrect it on next sync.
public struct SavedChart: Identifiable, Hashable, Codable, Sendable {

    /// Keys written by a **newer** app version, preserved verbatim.
    ///
    /// Without this, sync quietly destroys data. Version 2 writes a field version 1 has never heard
    /// of; version 1 opens that chart, the user renames it, and a plain `Codable` round-trip drops
    /// the field on save. The user loses something they never touched, on a device that reported no
    /// error, and neither app looks wrong. Round-tripping unknown keys makes an older client safe to
    /// read and write a newer record.
    ///
    /// Not part of `Hashable`/equality — two records differing only in fields this version cannot
    /// interpret are the same chart as far as this version is concerned.
    public var unknownKeys: [String: JSONValue] = [:]

    /// Stable across devices and renames. Also the filename — see `FileChartStore`.
    public let id: UUID
    /// Bumped when the shape of this struct changes. Present from record one so a future migration
    /// has something to branch on instead of guessing.
    public var schemaVersion: Int
    public var createdAt: Date
    /// Last-writer-wins needs this. Update it on every mutation, never by hand in the UI.
    public var modifiedAt: Date
    /// Non-nil means deleted. Filtered out of `all` but kept on disk so a delete can propagate.
    public var deletedAt: Date?

    /// What the user typed.
    public var name: String
    /// The birth instant, already resolved to absolute time using `timeZoneID` below.
    public var birthInstant: Date
    /// **The timezone the user chose, kept verbatim.**
    ///
    /// Never inferred from the coordinates. Historical DST and local mean time make place→zone
    /// resolution unsafe for older births, and a wrong zone moves the Ascendant by degrees while
    /// every number still looks plausible. Storing the identifier means a chart can be re-derived
    /// and audited later; storing only the instant would lose the evidence.
    public var timeZoneID: String

    /// False when the birth time is unknown — a first-class case, not an error.
    ///
    /// Houses, Ascendant and Midheaven are undefined without a time; planetary positions remain
    /// valid and useful. Anything reading this chart must branch on it rather than quietly showing
    /// angles computed from a default of noon, which is the failure that makes a chart look precise
    /// and be wrong.
    public var isTimeKnown: Bool

    public var latitude: Double
    public var longitude: Double
    public var placeName: String?

    public var location: GeoLocation {
        GeoLocation(latitude: latitude, longitude: longitude, name: placeName)
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .gmt }

    public init(id: UUID = UUID(),
                schemaVersion: Int = SavedChart.currentSchemaVersion,
                createdAt: Date = Date(),
                modifiedAt: Date = Date(),
                deletedAt: Date? = nil,
                name: String,
                birthInstant: Date,
                timeZoneID: String,
                isTimeKnown: Bool = true,
                latitude: Double,
                longitude: Double,
                placeName: String? = nil) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
        self.name = name
        self.birthInstant = birthInstant
        self.timeZoneID = timeZoneID
        self.isTimeKnown = isTimeKnown
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
    }

    public static let currentSchemaVersion = 1

    // MARK: - Codable, preserving what this version does not understand

    private enum Key: String, CodingKey, CaseIterable {
        case id, schemaVersion, createdAt, modifiedAt, deletedAt
        case name, birthInstant, timeZoneID, isTimeKnown
        case latitude, longitude, placeName
    }

    /// Any key that is not one of ours. Lets the decoder walk the whole object.
    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        id = try c.decode(UUID.self, forKey: .id)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        name = try c.decode(String.self, forKey: .name)
        birthInstant = try c.decode(Date.self, forKey: .birthInstant)
        timeZoneID = try c.decode(String.self, forKey: .timeZoneID)
        isTimeKnown = try c.decodeIfPresent(Bool.self, forKey: .isTimeKnown) ?? true
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        placeName = try c.decodeIfPresent(String.self, forKey: .placeName)

        // Everything else, kept as-is.
        let known = Set(Key.allCases.map(\.rawValue))
        let all = try decoder.container(keyedBy: AnyKey.self)
        var extras: [String: JSONValue] = [:]
        for key in all.allKeys where !known.contains(key.stringValue) {
            extras[key.stringValue] = try all.decode(JSONValue.self, forKey: key)
        }
        unknownKeys = extras
    }

    public func encode(to encoder: Encoder) throws {
        // Unknown keys first, so a corrupted extra can never shadow a field this version owns.
        var all = encoder.container(keyedBy: AnyKey.self)
        let known = Set(Key.allCases.map(\.rawValue))
        for (k, v) in unknownKeys where !known.contains(k) {
            try all.encode(v, forKey: AnyKey(stringValue: k))
        }

        var c = encoder.container(keyedBy: Key.self)
        try c.encode(id, forKey: .id)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try c.encode(name, forKey: .name)
        try c.encode(birthInstant, forKey: .birthInstant)
        try c.encode(timeZoneID, forKey: .timeZoneID)
        try c.encode(isTimeKnown, forKey: .isTimeKnown)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encodeIfPresent(placeName, forKey: .placeName)
    }

    public static func == (a: SavedChart, b: SavedChart) -> Bool {
        a.id == b.id && a.modifiedAt == b.modifiedAt && a.deletedAt == b.deletedAt
            && a.name == b.name && a.birthInstant == b.birthInstant
            && a.timeZoneID == b.timeZoneID && a.isTimeKnown == b.isTimeKnown
            && a.latitude == b.latitude && a.longitude == b.longitude
            && a.placeName == b.placeName
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(modifiedAt)
    }
}

// MARK: - Derived charts

public extension SavedChart {

    /// Positions at the birth instant — the natal chart proper.
    var positions: [BodyPosition] {
        CelestialBody.allCases.map {
            BodyPosition(body: $0,
                         longitude: Ephemeris.longitude(of: $0, at: birthInstant),
                         speed: Ephemeris.dailyMotion(of: $0, at: birthInstant))
        }
    }

    var aspects: [DetectedAspect] { Aspects.detect(in: positions, orbFactor: 1.0) }

    /// Nil when the birth time is unknown — deliberately, rather than defaulting to noon.
    func houses(system: HouseSystem) -> HouseCusps? {
        guard isTimeKnown else { return nil }
        return Houses.compute(at: birthInstant, location: location, system: system)
    }

    /// Transits to this chart: current sky against natal positions.
    func transits(at date: Date = Date(), orbFactor: Double = 1.0) -> [CrossAspect] {
        let now = CelestialBody.allCases.map {
            BodyPosition(body: $0,
                         longitude: Ephemeris.longitude(of: $0, at: date),
                         speed: Ephemeris.dailyMotion(of: $0, at: date))
        }
        return Aspects.detect(between: now, and: positions, orbFactor: orbFactor)
    }

    /// Synastry: this chart against another.
    func synastry(with other: SavedChart, orbFactor: Double = 1.0) -> [CrossAspect] {
        Aspects.detect(between: positions, and: other.positions, orbFactor: orbFactor)
    }
}
