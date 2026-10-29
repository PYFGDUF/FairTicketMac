import Foundation

/// One entry of the booking cart: a single alternative the engine may attempt.
///
/// The engine's version-5 configuration has no standalone station, train-list or
/// seat-list fields — `seat_types` is derived from the cart, and `from_station` /
/// `to_station` / `preferred_trains` are gone.  Mirroring the entry as a real type
/// rather than poking at a nested `JSONValue` is what keeps the editor able to add,
/// reorder and delete entries without every view re-deriving the shape.
///
/// `trainScope` is either `"specific"` (use `trainCode`) or `"all"` (accept any
/// train on that station pair).  The wording and the two values come from the
/// engine's `train_scopes` capability, so nothing here invents a scope the
/// validator would reject.
public struct CartItem: Equatable, Identifiable, Sendable {
    public static let scopeSpecific = "specific"
    public static let scopeAll = "all"

    public var fromStation: String
    public var toStation: String
    public var trainScope: String
    public var trainCode: String
    public var seatType: String

    /// Stable per-entry identity for `ForEach`.  The engine's own duplicate rule is
    /// "two entries with all five fields equal are a duplicate", so the fields are
    /// also the identity: two entries that compare equal are the same alternative.
    public var id: String {
        [fromStation, toStation, trainScope, trainCode, seatType].joined(separator: "\u{1}")
    }

    public init(
        fromStation: String = "",
        toStation: String = "",
        trainScope: String = CartItem.scopeAll,
        trainCode: String = "",
        seatType: String = ""
    ) {
        self.fromStation = fromStation
        self.toStation = toStation
        self.trainScope = trainScope
        self.trainCode = trainCode
        self.seatType = seatType
    }

    public init?(json: JSONValue) {
        guard let object = json.objectValue else { return nil }
        self.init(
            fromStation: object["from_station"]?.stringValue ?? "",
            toStation: object["to_station"]?.stringValue ?? "",
            // An unrecognised scope is read as "all", which is the value the engine
            // treats as the permissive default rather than silently switching to a
            // specific train the entry does not name.
            trainScope: object["train_scope"]?.stringValue == CartItem.scopeSpecific
                ? CartItem.scopeSpecific
                : CartItem.scopeAll,
            trainCode: object["train_code"]?.stringValue ?? "",
            seatType: object["seat_type"]?.stringValue ?? ""
        )
    }

    public var json: JSONValue {
        .object([
            "from_station": .string(fromStation),
            "to_station": .string(toStation),
            "train_scope": .string(trainScope),
            // An "all" entry must not carry a train code: the validator rejects the
            // combination outright ("不限车次项目不能同时指定车次").
            "train_code": .string(trainScope == CartItem.scopeSpecific ? trainCode : ""),
            "seat_type": .string(seatType),
        ])
    }

    /// True when the entry is complete enough to attempt, by the engine's own rules.
    public var isComplete: Bool {
        guard !fromStation.isEmpty, !toStation.isEmpty, !seatType.isEmpty else { return false }
        if trainScope == CartItem.scopeSpecific { return !trainCode.isEmpty }
        return true
    }

    public var scopeLabel: String {
        trainScope == CartItem.scopeSpecific ? trainCode : "不限车次"
    }
}

/// The engine's own description of what the current draft would attempt.
///
/// Every string is produced by the engine (`scope_summary`, `priority_preview`,
/// `cart_rows`), so the form and the start confirmation cannot promise an order the
/// engine would not perform — the attempt order *is* the cart order, and one success
/// ends the run.
public struct CartPreview: Decodable, Equatable, Sendable {
    /// One line per cart entry, worded exactly as the desktop window words it.
    public let cartRows: [String]
    public let cartCount: Int
    public let scopeSummary: String
    public let priorityPreview: String
    /// Seat products the cart would attempt, in cart order.
    public let seatTypes: [String]
    public let stationPairs: [[String]]
    public let trainCodes: [String]
    public let unlimitedScopeCount: Int
    public let hasSeated: Bool
    public let hasBerth: Bool
    public let passengerCount: Int

    private enum CodingKeys: String, CodingKey {
        case cartRows = "cart_rows"
        case cartCount = "cart_count"
        case scopeSummary = "scope_summary"
        case priorityPreview = "priority_preview"
        case seatTypes = "seat_types"
        case stationPairs = "station_pairs"
        case trainCodes = "train_codes"
        case unlimitedScopeCount = "unlimited_scope_count"
        case hasSeated = "has_seated"
        case hasBerth = "has_berth"
        case passengerCount = "passenger_count"
    }
}