import Foundation

/// One editable field, as described by the engine's `field_specs` payload.
///
/// The form is generated from this list rather than hard-coded, so a field added
/// on the Python side shows up here without a matching Swift change — and the
/// test suite over there fails if a spec goes missing.
public struct FieldSpec: Decodable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        case text
        case list
        case date
        case time
        case number
        case integer
        case toggle
        case choice
        /// The ordered cart of alternatives.  One control, because the engine's
        /// version-5 configuration has no separate station, train or seat fields:
        /// every journey choice lives inside a cart entry.
        case cart
        /// Per-passenger ticket type overrides (成人 / 学生 / 12306 默认).
        case ticketTypes = "ticket_types"
        case seatMap = "seat_map"
        case berths
    }

    public struct Option: Decodable, Equatable, Sendable {
        public let value: String
        public let label: String
    }

    public let key: String
    public let label: String
    public let page: String
    public let group: String
    public let kind: Kind
    public let help: String
    public let placeholder: String
    public let minimum: Double?
    public let maximum: Double?
    public let step: Double?
    public let decimals: Int
    public let suffix: String
    public let options: [Option]
    /// For `time` fields: the checkbox that switches the field off, which
    /// serialises to an empty string.
    public let optionalToggle: String
    /// `toggle` fields carry their sentence here instead of a separate label.
    public let inlineLabel: String
    /// Composite widgets can be configured but inactive; they must not be
    /// validated while their seat family is unselected.
    public let dormantUntil: String

    public var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key, label, page, group, kind, help, placeholder
        case minimum, maximum, step, decimals, suffix, options
        case optionalToggle = "optional_toggle"
        case inlineLabel = "inline_label"
        case dormantUntil = "dormant_until"
    }
}

/// A seat product the engine can order, with the query column and the order code.
public struct SeatSpec: Decodable, Equatable, Identifiable, Sendable {
    public let label: String
    public let stockKey: String
    public let submitCode: String

    public var id: String { label }

    private enum CodingKeys: String, CodingKey {
        case label
        case stockKey = "stock_key"
        case submitCode = "submit_code"
    }
}

/// Authoritative numeric bound from the backend validator.
public struct NumericRule: Decodable, Equatable, Identifiable, Sendable {
    public let key: String
    public let label: String
    public let minimum: Double
    public let maximum: Double
    public let inclusive: Bool
    public let integer: Bool

    public var id: String { key }
}

/// A labelled choice the backend defines, so no frontend invents its own wording.
///
/// Used for a cart entry's 车次范围 and for the per-passenger ticket type.  The
/// ticket-type list carries an empty value, which means "follow whatever the 12306
/// contact record says" rather than "unset".
public struct LabelledOption: Decodable, Equatable, Identifiable, Sendable {
    public let value: String
    public let label: String

    public var id: String { value }
}

/// Everything the engine tells a frontend about itself at handshake.
public struct Capabilities: Decodable, Equatable, Sendable {
    public struct SeatGroups: Decodable, Equatable, Sendable {
        public let seated: [String]
        public let berth: [String]
    }

    public struct SeatLayouts: Decodable, Equatable, Sendable {
        public let rows: [Int]
        public let lettersByCode: [String: [String]]
        public let choosableCodes: [String]
        public let businessCode: String

        private enum CodingKeys: String, CodingKey {
            case rows
            case lettersByCode = "letters_by_code"
            case choosableCodes = "choosable_codes"
            case businessCode = "business_code"
        }
    }

    public let `protocol`: Int
    public let engineVersion: String
    public let dataDir: String
    public let logFile: String
    /// The complete set of settings a frontend may edit.
    public let editableKeys: [String]
    public let defaults: [String: JSONValue]
    /// The form state the desktop window opens with, which is deliberately not
    /// `defaults`: it clears the seat selection and the train restriction.
    public let initialState: [String: JSONValue]
    public let fieldSpecs: [FieldSpec]
    public let groupOrder: [String]
    public let compositeKeys: [String]
    public let orderURL: String
    public let seats: [SeatSpec]
    public let seatGroups: SeatGroups
    public let seatLayouts: SeatLayouts
    /// A cart entry's 车次范围: 指定车次 / 不限车次.
    public let trainScopes: [LabelledOption]
    /// Per-passenger ticket types, including the empty "12306 默认" choice.
    public let ticketTypes: [LabelledOption]
    /// Ticket type name to the code the 12306 API expects.
    public let ticketTypeCodes: [String: String]
    public let logLevels: [String]
    public let numericRules: [NumericRule]
    public let maxPassengers: Int

    private enum CodingKeys: String, CodingKey {
        case `protocol`
        case engineVersion = "engine_version"
        case dataDir = "data_dir"
        case logFile = "log_file"
        case editableKeys = "editable_keys"
        case defaults
        case initialState = "initial_state"
        case fieldSpecs = "field_specs"
        case groupOrder = "group_order"
        case compositeKeys = "composite_keys"
        case orderURL = "order_url"
        case seats
        case seatGroups = "seat_groups"
        case seatLayouts = "seat_layouts"
        case trainScopes = "train_scopes"
        case ticketTypes = "ticket_types"
        case ticketTypeCodes = "ticket_type_codes"
        case logLevels = "log_levels"
        case numericRules = "numeric_rules"
        case maxPassengers = "max_passengers"
    }

    public func spec(for key: String) -> FieldSpec? {
        fieldSpecs.first { $0.key == key }
    }

    /// Fields for one sidebar group, in the backend's presentation order.
    public func specs(inGroup group: String) -> [FieldSpec] {
        fieldSpecs.filter { $0.group == group }
    }
}