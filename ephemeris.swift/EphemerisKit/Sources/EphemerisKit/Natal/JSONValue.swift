import Foundation



/// Any JSON value, decodable without knowing the shape.
///
/// This exists for one reason: **forward compatibility across app versions during sync.**
///
/// Once charts sync, two devices can run different app versions. Version 2 writes a field version 1
/// has never heard of. Version 1 opens that chart, the user renames it, and it is saved back — and
/// with a plain `Codable` struct the unknown field is silently gone. The user loses data they never
/// touched, on a device that reported no error, and nothing in either app is obviously wrong.
///
/// Preserving unknown keys verbatim makes the round-trip lossless, so an older client can read,
/// edit and re-save a newer record without destroying it. It is a few dozen lines now against a
/// class of corruption that is close to undebuggable later.
public enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unrepresentable JSON")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v):   try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v):  try c.encode(v)
        case .null:          try c.encodeNil()
        }
    }
}
