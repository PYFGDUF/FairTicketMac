import SwiftUI
import FairTicketKit

/// Presentation-only state: which sidebar section is showing, which seat groups
/// are expanded, and whether the inspector column is visible.
///
/// Kept apart from `AppModel` so a cross-view affordance — the berth editor's
/// "去选择卧铺席别" button, which has to switch section *and* expand a group — can
/// be expressed without teaching the booking state about navigation.
@MainActor
public final class UIState: ObservableObject {
    @Published var selectedSection: ConfigSection? = .trip
    @Published var showInspector = true
    /// The glanceable log tail under the form.
    ///
    /// Closed by default, matching the design: the log has its own page, and the form's
    /// own column is what the user is looking at while they fill it in.  Still here as a
    /// toggle — the View menu turns it back on — because a run the user is watching
    /// unfold is exactly when they want the tail in view without leaving the page.
    @Published var showsLogStrip = false

    /// Which 高级参数 groups the user has opened.  Empty means every group is
    /// collapsed, which is the default on purpose: fifteen fields that all have safe
    /// defaults should not present as a page that has to be worked through before the
    /// task can start.  Once opened, a group stays open.
    @Published var expandedAdvancedGroups: Set<String> = []

    /// Whether the cart's composer is open.
    ///
    /// Presentation state, so it lives here rather than on the model: with the composer
    /// open the cart page is a form, and what a returning user comes back for is the
    /// order of the entries.  Starting closed is the design's own arrangement.
    @Published var showsCartDraft = false

    /// Whether the cart's management table (reorder / edit / remove) is on screen.
    @Published var showsCartManager = false
    @Published var cartEditingID: String?

    func editCartItem(_ id: String) {
        cartEditingID = id
        showsCartManager = true
    }


    @Published var logFilter = ""
    @Published var warningsOnly = false

    /// The quietest level the log page shows.  `nil` means every level.
    ///
    /// A threshold rather than a set of ticks: the log is read by narrowing it — "just
    /// the warnings" — and nobody has ever wanted two non-adjacent levels.
    @Published var logThreshold: LogEntry.Level?

    /// True when the inspector was folded because the window got narrow, rather than
    /// by the user.  Widening the window brings it back only in that case, so a
    /// deliberate hide is never overridden.
    private var inspectorFoldedAutomatically = false

    public init() {}

    /// Version 5 has no seat page: seats are chosen inside a cart entry, so that is
    /// where "去选择卧铺席别" has to lead — and the entry's composer is closed by default,
    /// so leading to the page alone left the user looking at the entry list with no seat
    /// chips anywhere on it.
    func revealBerthSelection() {
        selectedSection = .cart
        showsCartDraft = true
    }

    func toggleInspector() {
        inspectorFoldedAutomatically = false
        showInspector.toggle()
    }

    /// Fold the inspector when three columns no longer fit.
    ///
    /// `Theme.inspectorCollapseWidth` is the width below which the form would have to
    /// go under its 500pt minimum (the seat grid needs it), so the inspector yields
    /// first — the form is what the user came for.
    ///
    /// Widths below the window's own minimum are ignored: the window reports
    /// placeholder sizes while it is being built, and folding on one of those would
    /// act on a size the user never saw.
    func adaptInspectorToWindowWidth(_ width: CGFloat) {
        guard width >= FairTicketWindow.minimumSize.width else { return }
        if width < Theme.inspectorCollapseWidth {
            guard showInspector else { return }
            inspectorFoldedAutomatically = true
            showInspector = false
        } else if inspectorFoldedAutomatically {
            inspectorFoldedAutomatically = false
            showInspector = true
        }
    }
}

/// The two seat families the form presents as collapsible groups.
enum SeatGroup {
    case seated
    case berth

    var name: String {
        switch self {
        case .seated: return "坐席"
        case .berth: return "卧铺"
        }
    }
}