import AppKit
import SwiftUI
import FairTicketKit

/// The window's navigation column.
///
/// Three tiers with a small caps label each — 开抢前设置 / 可选调整 / 运行 — so the
/// two pages that need no decision are visibly not part of the run-up.  A first-time
/// user should be able to close the window having never opened either of them.
///
/// Drawn by hand rather than as a `List(.sidebar)`: the system's source list draws its
/// selected row in the *system* accent, and neither `.tint` nor
/// `selectionHighlightStyle` reaches it, so this column was the one surface in the
/// window borrowed from another app.  A row here is a plain `Button` with the design's
/// own selected fill, which also lets it carry the two-line summary the design asks
/// for.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var ui: UIState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.motionEnabled) private var motionEnabled
    /// One shared identity for the selected row's fill, so switching sections slides the
    /// existing chip to the next row instead of fading one out and another in.  The
    /// system's own sidebars move their selection this way, and it is the difference
    /// between "the highlight travelled" and "the window redrawn".
    @Namespace private var selection
    /// Which row the keyboard is on.  Selection and focus move together: a list where
    /// the arrow keys move a highlight the user cannot see is a list that looks broken.
    @FocusState private var focusedSection: ConfigSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    group("开抢前设置", sections: ConfigSection.essential)
                    group("可选调整", sections: ConfigSection.optional)
                    group("运行", sections: ConfigSection.runtime)
                }
                .padding(.horizontal, SidebarMetrics.inset)
                .padding(.top, Theme.Space.lg)
                .padding(.bottom, Theme.Space.md)
                .animation(motionEnabled ? Theme.Motion.snappy : nil, value: ui.selectedSection)
            }

            Spacer(minLength: 0)

            enginePath
        }
        .frame(width: Theme.Layout.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.rail(scheme))
    }

    private enum SidebarMetrics {
        /// The column's own inset.  A row adds its own 10 on top, so a label sits 12
        /// from the edge and a row's title 22 — the design's arrangement.
        static let inset: CGFloat = 12
    }

    // MARK: Rows

    @ViewBuilder
    private func group(_ title: String, sections: [ConfigSection]) -> some View {
        Text(title)
            .font(Theme.ui(13, .medium))
            .foregroundStyle(Theme.textTertiary(scheme))
            .padding(.top, Theme.Space.lg)
            .padding(.bottom, Theme.Space.xs)

        VStack(alignment: .leading, spacing: 4) {
            ForEach(sections) { section in
                row(for: section)
            }
        }
    }

    private func row(for section: ConfigSection) -> some View {
        let selected = ui.selectedSection == section
        let errors = model.visibleErrorCount(in: section)

        return Button {
            ui.selectedSection = section
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(section.title)
                        .font(Theme.ui(16, selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Theme.accentText(scheme) : Theme.text(scheme))
                    if errors > 0 {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(Theme.ui(12))
                            .foregroundStyle(Theme.danger(scheme))
                            .help("该分组有 \(errors) 项参数需要修改")
                    }
                    Spacer(minLength: Theme.Space.xs)
                    if selected {
                        Image(systemName: "chevron.right")
                            .font(Theme.ui(12, .semibold))
                            .foregroundStyle(Theme.accentText(scheme))
                            .accessibilityHidden(true)
                    }
                }
                Text(summary(for: section))
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.textSecondary(scheme))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Theme.navigationSelection(scheme))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                                .strokeBorder(Theme.brandEdge(scheme), lineWidth: 1)
                        }
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityValue(selected ? "当前页面" : "")
        // HIG 5.2 / 5.7: ↑↓ walk the list.  Focus is what makes the arrow keys work,
        // and the focus ring is suppressed because the selected fill already says
        // where the user is — two indicators for one state is one too many.
        .focusable()
        .focusEffectDisabled()
        .focused($focusedSection, equals: section)
        .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
    }

    private func moveSelection(by offset: Int) {
        guard let current = ui.selectedSection,
              let next = current.neighbour(offset: offset) else { return }
        ui.selectedSection = next
        focusedSection = next
    }

    /// Where this destination stands in a first run is already said by the row's own
    /// summary; the design keeps the column free of a second indicator.

    // MARK: Footer

    /// Where the engine came from.
    ///
    /// Kept because "which Python is this actually driving" is the first question a
    /// broken run raises, and the answer is not visible anywhere else in the window.
    private var enginePath: some View {
        Text(model.engineSourceLabel.isEmpty ? "正在定位 Python 引擎" : model.engineSourceLabel)
            .font(Theme.data(13))
            .foregroundStyle(Theme.textTertiary(scheme))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, SidebarMetrics.inset + 10)
            .padding(.bottom, Theme.Space.md)
            .help(model.engineDescription)
    }

    // MARK: Summaries

    /// Each summary is derived from live settings, so the sidebar doubles as a
    /// glanceable readout of what the task will actually do.
    private func summary(for section: ConfigSection) -> String {
        switch section {
        case .cart:
            let items = model.cartItems
            if items.isEmpty { return "未加入备选" }
            let seats = model.cartSeatLabels().count
            return "\(items.count) 个备选 · \(seats) 种席别"

        case .trip:
            let date = model.string("train_date")
            if date.isEmpty { return "未选择日期" }
            return model.bool("auto_submit") ? "\(date) · 自动提交" : "\(date) · 仅监控"

        case .passengers:
            let people = model.listItems("passenger_names")
            return people.isEmpty ? "未填写（仅监控）" : "\(people.count) 位"

        case .position:
            if model.selectedSeatableProducts().isEmpty,
               model.selectedBerthProducts().isEmpty,
               !model.bool("quiet_carriage_preference") {
                return "未启用"
            }
            return "软偏好 · 不保证"

        case .advanced:
            guard let seconds = model.currentQueryInterval else { return "轮询 · 校时 · 超时" }
            return String(format: "当前间隔 %.2fs", seconds)

        case .log:
            // The design's own summary: how much there is, and how much of it is worth
            // reading first.
            let lines = model.logEntries.count
            guard lines > 0 else { return "已脱敏" }
            let warnings = model.logEntries.filter { $0.level.rank >= LogEntry.Level.warning.rank }.count
            return warnings > 0 ? "\(lines) 行 · \(warnings) 条警告" : "\(lines) 行"
        }
    }
}
