import Foundation

/// Arbitrary JSON, decoded without `Any`.
///
/// Engine event payloads are heterogeneous by design (a QR code arrives as a
/// tagged base64 object, metrics as numbers, stage hints as strings).  Modelling
/// them as `Any` would push unchecked casts into every view; this enum keeps the
/// decoding total and lets call sites ask for the shape they expect.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "无法识别的 JSON 值"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// Bridge from native values when assembling a settings payload.
    public static func from(_ value: Any) -> JSONValue {
        switch value {
        case let value as String: return .string(value)
        case let value as Bool: return .bool(value)
        case let value as Int: return .number(Double(value))
        case let value as Double: return .number(value)
        case let value as [String]: return .array(value.map { .string($0) })
        case let value as [Any]: return .array(value.map { JSONValue.from($0) })
        case let value as [String: Any]: return .object(value.mapValues { JSONValue.from($0) })
        case is NSNull: return .null
        default: return .string(String(describing: value))
        }
    }

    // MARK: Convenience accessors

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    public var intValue: Int? {
        guard let value = doubleValue, value.isFinite else { return nil }
        return Int(value)
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var stringArrayValue: [String]? {
        guard let items = arrayValue else { return nil }
        return items.compactMap(\.stringValue)
    }
}

/// A base64 image payload the engine tagged explicitly, so a QR code can never be
/// mistaken for ordinary text.
public struct TaggedBase64: Equatable, Sendable {
    public let data: Data

    public init?(json: JSONValue) {
        guard
            let object = json.objectValue,
            object["encoding"]?.stringValue == "base64",
            let encoded = object["data"]?.stringValue,
            let decoded = Data(base64Encoded: encoded)
        else { return nil }
        self.data = decoded
    }
}