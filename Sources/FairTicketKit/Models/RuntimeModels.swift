import Foundation

/// A progress event emitted by the booking engine.
///
/// The engine has twenty-one event kinds — twenty it sends plus the bridge's terminal
/// `exit` — with heterogeneous payloads.  Rather than twenty-one Swift types that would
/// have to be kept in step by hand, this keeps the wire payload intact and exposes typed
/// accessors for the fields the UI reads.
public struct RuntimeEvent: Decodable, Equatable, Sendable {

    public enum Kind: String, Sendable {
        case phase
        case clockSync = "clock_sync"
        case stations
        case qrReady = "qr_ready"
        case qrStatus = "qr_status"
        case query
        case candidate
        case passengers
        case orderWait = "order_wait"
        case orderSuccess = "order_success"
        case preferenceApplied = "preference_applied"
        case preferenceFallback = "preference_fallback"
        /// Which cart entry the engine is working through right now.
        case cartItem = "cart_item"
        /// An entry queried successfully and found nothing sellable.
        case queryEmpty = "query_empty"
        /// An entry's query round failed.
        case queryFailed = "query_failed"
        /// The server answered with trains whose stations do not match the request.
        case queryRouteMismatch = "query_route_mismatch"
        /// The outcome of the pre-run session check.
        case sessionChecked = "session_checked"
        /// Whether the engine will accept a maintenance request right now.
        ///
        /// Emitted on every change of the warm-up window's state, because the answer
        /// depends on where the run is: a code refresh is welcome while the engine is
        /// waiting, and refused while it is submitting an order.
        case maintenanceAvailability = "maintenance_availability"
        case finished
        case error
        /// Terminal frame owned by the bridge, not the engine.
        case exit
    }

    /// Stage reported through `phase` events.
    public enum Phase: String, Sendable {
        case preparing
        case clock
        case stations
        case login
        case waiting
        case querying
        case submitting
        case queueing
        case stopped
        case cancelled
        case failed

        /// The seven stages the status timeline displays, in order.
        public static let timeline: [Phase] = [
            .clock, .stations, .login, .waiting, .querying, .submitting, .queueing,
        ]

        public var title: String {
            switch self {
            case .preparing: return "正在准备"
            case .clock: return "服务器校时"
            case .stations: return "站点编码"
            case .login: return "扫码登录"
            case .waiting: return "等待热身窗口"
            case .querying: return "高频查票"
            case .submitting: return "提交订单"
            case .queueing: return "排队出票"
            case .stopped: return "任务已结束"
            case .cancelled: return "任务已停止"
            case .failed: return "任务失败"
            }
        }
    }

    public enum QRStatus: String, Sendable {
        case loggedIn = "logged_in"
        case waiting
        case scanned
        case confirmed
        case expired

        public var title: String {
            switch self {
            case .loggedIn: return "已登录，无需重新扫码"
            case .waiting: return "等待扫码"
            case .scanned: return "已扫码，等待手机端确认"
            case .confirmed: return "登录成功"
            case .expired: return "二维码已过期"
            }
        }
    }

    public let rawKind: String
    public let message: String
    public let data: [String: JSONValue]
    public let timestamp: Double

    public var kind: Kind? { Kind(rawValue: rawKind) }

    private enum CodingKeys: String, CodingKey {
        case kind, message, data, timestamp
    }

    /// Explicit initialiser: declaring `init(from:)` below suppresses the
    /// synthesised memberwise one, and the app needs to build a synthetic terminal
    /// event when the child dies without an `exit` frame.
    public init(
        rawKind: String,
        message: String = "",
        data: [String: JSONValue] = [:],
        timestamp: Double = 0
    ) {
        self.rawKind = rawKind
        self.message = message
        self.data = data
        self.timestamp = timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rawKind = try container.decode(String.self, forKey: .kind)
        message = (try? container.decode(String.self, forKey: .message)) ?? ""
        data = (try? container.decode([String: JSONValue].self, forKey: .data)) ?? [:]
        timestamp = (try? container.decode(Double.self, forKey: .timestamp)) ?? 0
    }

    // MARK: Typed accessors

    public var phase: Phase? {
        guard let raw = data["phase"]?.stringValue else { return nil }
        return Phase(rawValue: raw)
    }

    public var qrStatus: QRStatus? {
        guard let raw = data["status"]?.stringValue else { return nil }
        return QRStatus(rawValue: raw)
    }

    /// The countdown's only time source: the engine reports the release moment as
    /// a server-clock timestamp when it enters the warm-up window.
    public var targetTimestamp: Double? { data["target_timestamp"]?.doubleValue }
    public var queryStartTimestamp: Double? { data["query_start_timestamp"]?.doubleValue }

    public var qrImageData: Data? { TaggedBase64(json: data["image_bytes"] ?? .null)?.data }
    public var qrExpiresAt: Double? { data["expires_at"]?.doubleValue }

    public var clockOffsetSeconds: Double? { data["offset_seconds"]?.doubleValue }
    public var clockRTTMilliseconds: Double? { data["rtt_ms"]?.doubleValue }

    public var queryAttempt: Int? { data["attempt"]?.intValue }
    public var queryMaxRetries: Int? { data["max_retries"]?.intValue }
    public var queryIntervalSeconds: Double? { data["interval_seconds"]?.doubleValue }

    public var candidateTrain: String? { data["train"]?.stringValue }
    public var candidateSeatLabel: String? { data["seat_label"]?.stringValue }
    public var candidateStock: String? { data["stock"]?.stringValue }
    /// "HH:mm" as the server prints it, not a timestamp.
    public var candidateStartTime: String? { data["start_time"]?.stringValue }
    public var candidateArriveTime: String? { data["arrive_time"]?.stringValue }
    public var candidateDuration: String? { data["duration"]?.stringValue }

    /// `query_route_mismatch` payload: how many rows the server returned for the wrong
    /// station pair.
    public var rejectedRouteCount: Int? { data["rejected_count"]?.intValue }

    /// `session_checked` payload: `valid`, `expired` or `failed`.
    public var sessionState: String? { data["state"]?.stringValue }

    public var orderID: String? {
        // The engine reports `order_id`; tolerate `orderId` for forward safety.
        data["order_id"]?.stringValue ?? data["orderId"]?.stringValue
    }

    public var waitSeconds: Double? { data["wait_time"]?.doubleValue }
    public var availablePassengerCount: Int? { data["available_count"]?.intValue }

    /// `maintenance_availability` payload.  Read as optionals so a frame that omits a
    /// field leaves the client's previous answer alone rather than resetting it.
    public var maintenanceEnabled: Bool? { data["enabled"]?.boolValue }
    public var maintenanceBusy: Bool? { data["busy"]?.boolValue }
    public var maintenanceLoginRequired: Bool? { data["login_required"]?.boolValue }
    public var preferenceSeats: String? { data["choose_seats"]?.stringValue }
    public var preferenceDetailType: String? { data["seat_detail_type"]?.stringValue }
    public var exceptionType: String? { data["exception_type"]?.stringValue }
    public var exitCode: Int? { data["exit_code"]?.intValue }
    public var isSafeStop: Bool { data["safe_stop"]?.boolValue ?? false }
    public var wasCancelled: Bool { data["cancelled"]?.boolValue ?? false }
}

/// How a run ended.  Produced from the bridge's terminal `exit` frame.
public struct RunOutcome: Equatable, Sendable {
    public let exitCode: Int
    /// The server may already hold the reservation, so the engine refused to try
    /// another candidate.  The UI must block and point at the official order page.
    public let safeStop: Bool
    public let exceptionType: String
    public let cancelled: Bool
    public let message: String

    public init(event: RuntimeEvent) {
        exitCode = event.exitCode ?? 1
        safeStop = event.isSafeStop
        exceptionType = event.exceptionType ?? ""
        cancelled = event.wasCancelled
        message = event.message
    }

    public var succeeded: Bool { exitCode == 0 }
    public var wasStoppedByUser: Bool { exitCode == 130 || cancelled }
}

/// A batch of already-redacted log lines from the engine's log pipeline.
public struct LogEntry: Equatable, Identifiable, Sendable {
    public enum Level: String, Sendable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case critical = "CRITICAL"

        public init(tag: String) {
            self = Level(rawValue: tag.uppercased()) ?? .info
        }
    }

    public let id: UUID
    public let text: String
    public let level: Level

    public init(text: String, levelTag: String) {
        self.id = UUID()
        self.text = text
        self.level = Level(tag: levelTag)
    }
}

/// Result of a validation pass.  Keys are canonical settings keys.
public struct ValidationResult: Decodable, Equatable, Sendable {
    public let valid: Bool
    public let errors: [String: String]
}

/// Result of a start request.  A rejected start returns field errors instead of
/// running, which is how the desktop form reports problems without a modal.
public struct StartResult: Decodable, Equatable, Sendable {
    public let started: Bool
    public let errors: [String: String]

    private enum CodingKeys: String, CodingKey { case started, errors }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        started = (try? container.decode(Bool.self, forKey: .started)) ?? false
        errors = (try? container.decode([String: String].self, forKey: .errors)) ?? [:]
    }
}