import Foundation

/// A correlated response to a command.
public struct Reply {
    public let id: Int?
    public let ok: Bool
    public let result: JSONValue
    public let error: String?
    public let errorType: String?

    public var resultObject: [String: JSONValue] { result.objectValue ?? [:] }

    /// Re-decode the `result` payload into a concrete model.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// One decoded line from the bridge's stdout.
public enum SidecarFrame {
    case hello(Capabilities)
    case reply(Reply)
    case event(RuntimeEvent)
    case log([LogEntry])

    /// Header shared by every frame, used to pick the concrete decoder.
    private struct Header: Decodable {
        let type: String
        let id: Int?
        let ok: Bool?
        let error: String?
        let errorType: String?

        private enum CodingKeys: String, CodingKey {
            case type, id, ok, error
            case errorType = "error_type"
        }
    }

    private struct LogFrame: Decodable {
        /// Each entry is `[line, level]`.
        let lines: [[String]]
    }

    private struct ReplyEnvelope: Decodable {
        let result: JSONValue?
    }

    /// Decode one protocol line.  Returns `nil` for a line that is not a frame,
    /// which the reader treats as a corrupt line rather than a fatal error: the
    /// bridge redirects stray output to stderr, but a defensive reader must not
    /// die on an unexpected byte.
    public static func decode(line: String) -> SidecarFrame? {
        guard let data = line.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else { return nil }

        switch header.type {
        case "hello":
            guard let capabilities = try? decoder.decode(Capabilities.self, from: data) else {
                return nil
            }
            return .hello(capabilities)

        case "reply":
            let envelope = try? decoder.decode(ReplyEnvelope.self, from: data)
            return .reply(
                Reply(
                    id: header.id,
                    ok: header.ok ?? false,
                    result: envelope?.result ?? .object([:]),
                    error: header.error,
                    errorType: header.errorType
                )
            )

        case "event":
            guard let event = try? decoder.decode(RuntimeEvent.self, from: data) else {
                return nil
            }
            return .event(event)

        case "log":
            guard let frame = try? decoder.decode(LogFrame.self, from: data) else { return nil }
            let entries = frame.lines.compactMap { pair -> LogEntry? in
                guard pair.count >= 2 else { return nil }
                return LogEntry(text: pair[0], levelTag: pair[1])
            }
            return .log(entries)

        default:
            return nil
        }
    }
}