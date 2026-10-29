import SwiftUI
import FairTicketKit

/// The sidebar's configuration destinations.
///
/// Version 5 of the engine's configuration is built around an ordered *cart*: one
/// list of alternatives, each naming its own stations, train scope and seat.  That
/// replaced the old single-route form outright — `from_station`, `to_station`,
/// `preferred_trains`, `only_preferred_trains` and `seat_types` no longer exist, so
/// the pages that edited them (行程与乘车人's station row, 车次范围, 席别与优先级) are
/// gone too.  What is left is the same three-tier sidebar it always was, with the
/// cart holding everything the old train and seat pages used to.
///
/// A sidebar rather than tabs, because the layout's whole point is that you tune
/// parameters while watching the countdown in the live inspector.
enum ConfigSection: String, CaseIterable, Identifiable, Hashable {
    case cart
    case trip
    case passengers
    case position
    case advanced
    case log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cart: return "备选购物车"
        case .trip: return "行程时间"
        case .passengers: return "乘车人"
        case .position: return "座位与铺位"
        case .advanced: return "高级参数"
        case .log: return "运行日志"
        }
    }

    /// The page's own heading, above the form.
    ///
    /// A sentence about what the page does rather than a restatement of its name: the
    /// sidebar already says 备选购物车, so the heading says what the alternatives *do*.
    /// The split is the design document's — the small orange label carries the
    /// destination, the large line carries the meaning.
    var headline: String {
        switch self {
        case .cart: return "按顺序尝试的备选"
        case .trip: return "到点开始，到点安全停止"
        case .passengers: return "只填姓名，票种沿用记录"
        case .position: return "软偏好，不保证兑现"
        case .advanced: return "默认值可直接使用，仅必要时调整"
        case .log: return "运行日志"
        }
    }

    /// The one sentence of guidance under the heading.
    var lead: String {
        switch self {
        case .cart: return "任意一项出票成功后，其余备选自动停止。优先级从上到下。"
        case .trip: return "立即开始、不设停止时间，或指定一个安全停止时刻均可。"
        case .passengers: return "填 1–5 个已在当前 12306 账户中的姓名；票种留空即沿用账户记录。"
        case .position: return "偏好只提交一次；若 12306 未开放或无法满足，订单仍保留并由系统分配其他位置。"
        case .advanced: return "频率过高可能导致限流。除非确有需要，建议保持默认值。"
        case .log: return "引擎全量输出已脱敏，可按级别筛选、复制或导出。"
        }
    }

    var systemImage: String {
        switch self {
        case .cart: return "cart.fill"
        case .trip: return "calendar"
        case .passengers: return "person.2.fill"
        case .position: return "rectangle.split.3x1"
        case .advanced: return "slider.horizontal.3"
        case .log: return "text.alignleft"
        }
    }

    /// Grouped headings in the sidebar, in presentation order.
    ///
    /// Three tiers rather than two, because the six destinations are not equally
    /// important to someone opening this for the first time: four of them are peers in
    /// the old flat list, so 高级参数 — a dozen fields with safe defaults — looked as
    /// much like something you must visit as 备选购物车 did.  The split follows what
    /// the engine already says about the fields themselves: 座位与铺位 is a soft
    /// preference the engine reports back when it cannot honour it, and the 查询与热身
    /// page's own guidance is to keep the defaults.
    static let essential: [ConfigSection] = [.cart, .trip, .passengers]
    static let optional: [ConfigSection] = [.position, .advanced]
    static let runtime: [ConfigSection] = [.log]

    /// Every section the form can render, in shortcut order.
    static var configuration: [ConfigSection] { essential + optional }

    // MARK: Key ownership

    /// Which canonical settings keys each section owns.
    ///
    /// Kept next to the section rather than inside the view because the start
    /// confirmation also needs it: a rejected start has to send the user to the
    /// page holding the first bad field, and the two must not disagree about where
    /// a field lives.
    static let cartKeys: Set<String> = ["cart_items"]
    static let tripKeys: Set<String> = [
        "train_date", "start_at", "stop_at", "auto_submit",
    ]
    static let passengerKeys: Set<String> = ["passenger_names", "passenger_ticket_types"]
    static let positionKeys: Set<String> = [
        "seat_position_preferences", "berth_preference", "quiet_carriage_preference",
    ]

    static var claimedKeys: Set<String> {
        cartKeys.union(tripKeys).union(passengerKeys).union(positionKeys)
    }

    static func keys(for section: ConfigSection) -> Set<String> {
        switch section {
        case .cart: return cartKeys
        case .trip: return tripKeys
        case .passengers: return passengerKeys
        case .position: return positionKeys
        case .advanced, .log: return []
        }
    }

    /// The section `offset` steps away in the order the sidebar draws.
    ///
    /// HIG 5.7 wants ↑↓ to walk a list, and the sidebar is the app's list.  The rule
    /// lives here, apart from the key handling, so the order and the ends of the list can
    /// be asserted without a keyboard.
    func neighbour(offset: Int) -> ConfigSection? {
        let order = Self.allCases
        guard let index = order.firstIndex(of: self) else { return nil }
        let target = index + offset
        guard order.indices.contains(target) else { return nil }
        return order[target]
    }

    /// The section that owns a field, or nil when it falls through to 高级参数.
    static func owning(_ key: String) -> ConfigSection? {
        for section in configuration where keys(for: section).contains(key) {
            return section
        }
        return nil
    }

    /// Every settings key the form can actually reach, given what the engine offers.
    ///
    /// The form is generated from `field_specs`, and each spec lands on a page either
    /// because its section claims it or because 高级参数 picks up whatever is left —
    /// this mirrors that rule so it can be asserted without a window.
    ///
    /// The rule matters because the fall-through is the only thing standing between a
    /// backend field and a field nobody can edit: a spec whose group never reaches a
    /// page is silently unreachable, and the failure looks like nothing at all.
    static func reachableKeys(in capabilities: Capabilities) -> Set<String> {
        var keys = claimedKeys
        for group in capabilities.groupOrder {
            for spec in capabilities.specs(inGroup: group) where !claimedKeys.contains(spec.key) {
                keys.insert(spec.key)
            }
        }
        return keys
    }
}