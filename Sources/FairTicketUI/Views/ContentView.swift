import SwiftUI
import UniformTypeIdentifiers
import FairTicketKit

/// Identifies the app's windows.
///
/// Lives here rather than in the app target so the menu bar item — which lives in
/// this library — can reopen the window without the library depending on the app,
/// and so the About command and the About scene agree on one identifier.
public enum FairTicketWindow {
    public static let mainID = "main"

    /// The About panel.  A singleton scene, so there is no way to end up with two
    /// windows making the same claim about the version.
    public static let aboutID = "about"

    /// Smallest window the three-column layout still works in.  Below this the
    /// inspector folds automatically, but the window itself must not be allowed to
    /// shrink past the point where the seat grid can be drawn.
    public static let minimumSize = CGSize(width: 980, height: 620)
}

/// Root layout, in the design document's five bands.
///
///     ┌ top bar ────────────────────────────────────────────┐
///     ├ sidebar ─┬─ main pane ─────────────┬─ task status ─┤
///     └ bottom bar ─────────────────────────────────────────┘
///
/// Both bars span the full width, which is why this is a plain `VStack` of `HStack`s
/// rather than a `NavigationSplitView`: a split view owns its toolbar and its
/// inspector, so the two bars could only ever be as wide as the detail column, and the
/// brand and the primary action would end up under AppKit's own title-bar chrome.
///
/// The task-status column is kept — the design keeps it too — because the countdown
/// has to stay on screen while the form is edited.  It is the window's second pane in
/// both arrangements; only the chrome around it changed.
///
/// Both state objects are owned by the `App`, because the menu bar drives the same
/// engine: a second model here would mean two child processes and two logins.
public struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var ui: UIState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        ZStack {
            chrome

            // The result panel floats over the window rather than being presented as a
            // sheet: a sheet is its own window, so it could not be captured in a
            // screenshot of this one, and this screen is reviewed far more often than it
            // is reached for real.
            if let outcome = finishedOutcome, frontPanel == .result {
                Color.black.opacity(scheme == .dark ? 0.55 : 0.25)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { model.acknowledgeOutcome() }

                RunResultView(
                    outcome: outcome,
                    onClose: { model.acknowledgeOutcome() },
                    onOpenOrders: { openOrderPage() },
                    onAdjust: {
                        model.acknowledgeOutcome()
                        ui.selectedSection = .cart
                    }
                )
                .environmentObject(model)
                .padding(.vertical, Theme.Space.md)
                .transition(Theme.Motion.panel)
            }

            // The pre-start briefing.  Presented over the window for the same reason as
            // the result panel — and because the desktop form must always show what the
            // draft would attempt before it starts: there is no path from a button to a
            // running task that skips this.
            if let summary = model.pendingStart, frontPanel == .briefing {
                Color.black.opacity(scheme == .dark ? 0.55 : 0.25)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { model.cancelStart() }

                StartConfirmationView(
                    summary: summary,
                    onConfirm: { Task { await model.confirmStart() } },
                    onCancel: { model.cancelStart() }
                )
                .transition(Theme.Motion.panel)
            }

            // The cart's management table: reorder, edit, remove.  Over the window like
            // the other two panels, so a screenshot of the window shows it.
            if ui.showsCartManager, frontPanel == .manager {
                Color.black.opacity(scheme == .dark ? 0.55 : 0.25)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { ui.showsCartManager = false }

                CartManagerView(onClose: { ui.showsCartManager = false })
                    .environmentObject(model)
                    .environmentObject(ui)
                    .transition(Theme.Motion.panel)
            }
        }
        .motion(Theme.Motion.smooth, value: model.runState)
        // The panels above declare transitions, but a transition only plays inside an
        // animation, and `runState` does not change when one of them opens.  This is the
        // one value that does: which panel is on top.  Without it the briefings appeared
        // instantly and — worse for the result panel, which is closed by a button rather
        // than by a state change — vanished instantly too.
        .motion(Theme.Motion.smooth, value: frontPanel)
        // Same for the third column, which the View menu and ⌥I fold away: its
        // `.move(edge: .trailing)` had no animation to run inside, so the pane snapped.
        .motion(Theme.Motion.smooth, value: ui.showInspector)
        // A live run owns the window, so the panels that belong to *before* the run end
        // with it.  Started from the menu bar, the cart table used to reappear over a
        // running task — where its 删除/编辑 controls mutate the very cart the engine is
        // submitting orders from, while every equivalent form control is frozen.
        .onChange(of: model.isRunning) { _, running in
            guard running else { return }
            ui.showsCartManager = false
            ui.showsCartDraft = false
            model.cancelStart()
        }
        .background(Theme.canvas(scheme))
        // Window width comes from AppKit notifications, not from measuring layout.
        // Measuring inside the view tree meant folding the inspector *during* a layout
        // pass, which AppKit answers by throwing ("needs another layout pass") and the
        // app dies on the breakpoint — see the crash log for
        // `_postWindowNeedsUpdateConstraints`.  A resize notification arrives outside
        // layout, so the decision never touches the view graph mid-pass.
        .background(WindowWidthReporter { width in
            ui.adaptInspectorToWindowWidth(width)
        })
        // One accent for the whole window: selection, toggles, links and badges all
        // take the brand orange, so nothing else in the app introduces a hue.
        .tint(Theme.brand)
        .font(Theme.value)
        // Every animation in the window reads this, so Reduce Motion is honoured in one
        // place instead of at twenty.
        .environment(\.motionEnabled, !reduceMotion)
        // Lets the View menu drive section switching with ⌘1…⌘6.
        .focusedSceneValue(\.uiState, ui)
        // What the File and 任务 menus need.  The availability snapshot is separated from
        // the model so a menu does not observe a countdown that ticks ten times a second.
        .focusedSceneValue(\.appModel, model)
        .focusedSceneValue(\.taskAvailability, TaskCommandAvailability(model: model))
        .task {
            await model.connect()
            // Open where the work is.  The window used to open on 行程时间 regardless of
            // what the draft still needed, which put a first-time user in front of a time
            // field when the thing they had not done yet was adding a route.
            if let next = SetupProgress(model: model).next {
                ui.selectedSection = next
            }
            #if DEBUG
            // Screenshot-only switches; see `ReviewHooks`.  Absent from release builds,
            // inert unless the environment asks for something.
            ReviewHooks.apply(model: model, ui: ui)
            #endif
        }
        // A failed connection must be visible; a silently blank window is the
        // hardest state to diagnose.
        .alert(
            "引擎连接失败",
            isPresented: Binding(
                get: { if case .failed = model.engineState { return true } else { return false } },
                set: { _ in }
            )
        ) {
            Button("重试") { Task { await model.connect() } }
        } message: {
            if case .failed(let message) = model.engineState { Text(message) }
        }
        // A refused start names the first bad field and moves the window to the
        // page holding it, so the message is actionable rather than a count.
        .alert(
            "配置需要修改",
            isPresented: Binding(
                get: { model.startBlockedMessage != nil },
                set: { if !$0 { model.clearStartBlock() } }
            )
        ) {
            Button("好", role: .cancel) { model.clearStartBlock() }
        } message: {
            Text(model.startBlockedMessage ?? "")
        }
        // A safe stop is *not* an alert any more: the engine refusing to continue is one
        // of the three ways a run can end, so it is presented by `RunResultView` with
        // the same weight as a success and with the run's own numbers beside it.  An
        // alert put the app's most consequential sentence in a system box with one
        // button and no context.
    }

    /// The window's own bands, under any overlay.
    ///
    /// No rules between the bands: the rail is one step lighter than the canvas, and
    /// that tone step is the whole separation the design draws.
    private var chrome: some View {
        VStack(spacing: 0) {
            TopBar()
                .environmentObject(model)
                .environmentObject(ui)

            HStack(spacing: 0) {
                SidebarView()
                    .environmentObject(model)
                    .environmentObject(ui)

                DetailView(showsLogStrip: $ui.showsLogStrip)
                    .environmentObject(model)
                    .environmentObject(ui)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if ui.showInspector {
                    InspectorView()
                        .environmentObject(model)
                        .environmentObject(ui)
                        .frame(width: Theme.Layout.inspectorWidth)
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(maxHeight: .infinity)

            BottomBar()
                .environmentObject(model)
                .environmentObject(ui)
        }
    }

    /// The run's terminal state, if it has one.
    private var finishedOutcome: RunOutcome? {
        if case .finished(let outcome) = model.runState { return outcome }
        return nil
    }

    /// Which floating panel the window draws.
    ///
    /// One decision, read by all three branches above.  They used to each carry their own
    /// guard, and the copies were not the same: the briefing and the cart table both
    /// demanded that no run had *ever* finished, while nothing clears a finished run —
    /// closing its panel only records the outcome as dismissed.  So after a single run,
    /// 开始任务 and 管理购物车 went permanently dead, silently, with the form otherwise
    /// usable again.
    enum FrontPanel: Equatable {
        case none
        case result
        case briefing
        case manager

        static func of(
            outcomeNeedsReview: Bool,
            hasPendingStart: Bool,
            showsCartManager: Bool
        ) -> FrontPanel {
            if outcomeNeedsReview { return .result }
            if hasPendingStart { return .briefing }
            if showsCartManager { return .manager }
            return .none
        }
    }

    private var frontPanel: FrontPanel {
        FrontPanel.of(
            outcomeNeedsReview: model.outcomeNeedsReview && finishedOutcome != nil,
            hasPendingStart: model.pendingStart != nil,
            showsCartManager: ui.showsCartManager
        )
    }

    private func openOrderPage() {
        if let url = model.orderURL {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Reports the host window's width, and its changes, without measuring SwiftUI
/// layout.
///
/// Invisible and inert: it exists so the inspector's auto-fold can be decided from a
/// real window resize instead of from a geometry read taken during layout.  The
/// difference is not stylistic — the geometry version mutated observable state inside
/// a layout pass and crashed the app in `_postWindowNeedsUpdateConstraints`.
private struct WindowWidthReporter: NSViewRepresentable {
    let onWidth: (CGFloat) -> Void

    func makeNSView(context: Context) -> ReporterView {
        let view = ReporterView()
        view.onWidth = onWidth
        return view
    }

    func updateNSView(_ view: ReporterView, context: Context) {
        view.onWidth = onWidth
    }

    final class ReporterView: NSView {
        var onWidth: ((CGFloat) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            guard let window else { return }
            report(window.frame.width)
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self, let window = self.window else { return }
                self.report(window.frame.width)
            }
        }

        /// Hand the width over on the next runloop turn.
        ///
        /// `viewDidMoveToWindow` runs *inside* AppKit's layout of the new window, and
        /// reacting there means changing observable state mid-pass — which AppKit
        /// answers by throwing out of `_postWindowNeedsUpdateConstraints` ("more layout
        /// passes than there were iterations") and taking the app down before the
        /// window is on screen.
        private func report(_ width: CGFloat) {
            DispatchQueue.main.async { [weak self] in
                self?.onWidth?(width)
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

/// The pre-start confirmation.
///
/// Laid out as the design's briefing: what the run will do, in the order a traveller
/// checks it — the date and route, who is going, which trains will be tried and in what
/// order, and the rules the engine will apply.  The two engine strings are shown
/// verbatim because they encode real decision rules.
///
/// It is the app's one full-attention moment before anything is submitted, so it is a
/// panel over the window rather than a sheet: the same construction as the result panel,
/// which means the two ends of a run are reviewed and captured the same way.
struct StartConfirmationView: View {
    let summary: StartSummary
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    routeSection
                    passengerSection
                    if !summary.cartRows.isEmpty { candidatesSection }
                    rulesSection
                }
                .padding(Theme.Space.lg)
            }
            .frame(maxHeight: 580)
            footer
        }
        .frame(width: 560)
        .background(
            Theme.card(scheme),
            in: RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .strokeBorder(Theme.hairline(scheme), lineWidth: 1)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.22), radius: 30, y: 12)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("CONFIRM START")
                .font(Theme.data(13, .semibold))
                .tracking(1.6)
                .foregroundStyle(Theme.accentText(scheme))
            Text("确认开始抢票任务")
                .font(Theme.ui(22, .semibold))
                .foregroundStyle(Theme.textStrong(scheme))
            Text("任务启动后将持续查询并可能自动提交订单。运行中可重新获取二维码，停止后可重新登录。")
                .font(Theme.ui(15))
                .foregroundStyle(Theme.textSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.lg)
        .padding(.top, Theme.Space.lg)
        .padding(.bottom, Theme.Space.sm)
    }

    // MARK: Sections

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.ui(13, .medium))
            .foregroundStyle(Theme.textTertiary(scheme))
    }

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            sectionTitle("行程路线")
            VStack(spacing: 0) {
                factRow("乘车日期", summary.date.isEmpty ? "未选择" : summary.date)
                rule
                factRow("出发 → 到达", summary.route.isEmpty ? "未填写" : summary.route)
                rule
                // The window is the one line here that decides when the run moves, so it
                // carries the brand colour the design gives it.
                factRow(
                    "提交时间窗",
                    summary.submitWindow.isEmpty ? "立即开始 – 不设停止时间" : summary.submitWindow,
                    valueTint: Theme.brand
                )
            }
            .panelWell
        }
    }

    private var passengerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            sectionTitle("乘车人与席别")
            VStack(spacing: 0) {
                if passengers.isEmpty {
                    factRow("乘车人", "未填写（仅监控）")
                } else {
                    ForEach(Array(SummaryLine.identify(passengers).enumerated()), id: \.element.id) { index, line in
                        if index > 0 { rule }
                        numberedRow(index: index, name: line.text, trailing: seatLine)
                    }
                }
            }
            .panelWell
        }
    }

    private var candidatesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            sectionTitle("本轮备选车次 · 按顺序尝试")
            VStack(spacing: 0) {
                ForEach(Array(SummaryLine.identify(summary.cartRows).enumerated()), id: \.element.id) { index, line in
                    if index > 0 { rule }
                    numberedRow(
                        index: index,
                        name: line.text,
                        trailing: index == 0 ? "首选" : "备选",
                        trailingTint: index == 0 ? Theme.brand : nil
                    )
                }
            }
            .panelWell
        }
    }

    /// 尝试规则: the three rules the engine will apply, in the design's order.
    ///
    /// 任务模式 belongs here rather than with the route: it is not part of *what* is
    /// being attempted, it is how the attempt behaves once a ticket is found.
    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            sectionTitle("尝试规则")
            VStack(spacing: 0) {
                factRow(
                    "任务模式",
                    summary.mode == "仅监控" ? "仅监控，不提交订单" : "自动提交订单",
                    valueTint: summary.mode == "仅监控" ? nil : Theme.brand
                )
                rule
                if !summary.position.isEmpty {
                    factRow("座位位置偏好", summary.position)
                    rule
                }
                factRow("本项提交失败时", "顺延下一备选车次")
                rule
                factRow("任意一项出票成功后", "停止任务，其余备选不再尝试")
            }
            .panelWell

            InlineNote(text: modeWarning, tone: summary.mode == "仅监控" ? .neutral : .warning)
        }
    }

    private var modeWarning: String {
        summary.mode == "仅监控"
            ? "当前为「仅监控」模式：只查询余票，不会向 12306 提交任何订单。"
            : "当前为「自动提交」模式：命中余票后将直接向 12306 提交订单。请确认乘车人与日期无误。"
    }

    private var passengers: [String] {
        summary.passengers
            .split(whereSeparator: { $0 == "、" || $0 == "，" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The seat products the run would try, stated once beside the passengers.
    ///
    /// Taken from the cart through `StartSummary.seatLabels`.  The dialog used to
    /// extract these words from the engine's own cart rows, which produced an empty
    /// column the moment a row's wording changed — the cart is the authority, so it is
    /// asked directly.
    private var seatLine: String {
        summary.seatLabels.prefix(2).joined(separator: " · ")
    }

    // MARK: Rows

    private var rule: some View {
        Rectangle()
            .fill(Theme.divider(scheme))
            .frame(height: 1)
            .padding(.leading, Theme.Space.sm)
    }

    private func factRow(_ label: String, _ value: String, valueTint: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
            Text(label)
                .font(Theme.ui(14))
                .foregroundStyle(Theme.textTertiary(scheme))
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(Theme.ui(15, .medium))
                .foregroundStyle(valueTint ?? Theme.textStrong(scheme))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 11)
    }

    private func numberedRow(
        index: Int,
        name: String,
        trailing: String,
        trailingTint: Color? = nil
    ) -> some View {
        HStack(spacing: Theme.Space.sm) {
            SequenceBadge(value: index + 1, emphasised: index == 0)
            Text(name)
                .font(Theme.ui(15, .medium))
                .foregroundStyle(Theme.text(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.xs)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(Theme.ui(14, .medium))
                    .foregroundStyle(trailingTint ?? Theme.textSecondary(scheme))
            }
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 9)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: Theme.Space.xs) {
            Text("Esc 取消 · 确认启动后可在菜单栏停止任务")
                .font(Theme.ui(14))
                .foregroundStyle(Theme.textTertiary(scheme))
            Spacer(minLength: Theme.Space.xs)
            Button("取消") { onCancel() }
                .buttonStyle(.chipAction(height: 32))
                .keyboardShortcut(.cancelAction)
            Button("开始抢票") { onConfirm() }
                .buttonStyle(.brandAction(height: 32))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
        .background(alignment: .top) {
            Rectangle().fill(Theme.hairline(scheme)).frame(height: 1)
        }
    }
}

/// The nested card the design uses inside a panel: one step below the panel's own
/// surface, which is what makes the rows read as a table rather than as loose text.
private extension View {
    var panelWell: some View {
        modifier(PanelWell())
    }
}

private struct PanelWell: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(
                Theme.well(scheme),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.hairline(scheme), lineWidth: 1)
            )
    }
}

/// Stable row identity for immutable briefing text, including repeated passenger
/// names. The occurrence suffix only distinguishes identical labels in this snapshot.
struct SummaryLine: Identifiable {
    let id: String
    let text: String

    static func identify(_ values: [String]) -> [SummaryLine] {
        var occurrences: [String: Int] = [:]
        return values.map { value in
            let occurrence = occurrences[value, default: 0]
            occurrences[value] = occurrence + 1
            return SummaryLine(id: "\(value)\u{1F}\(occurrence)", text: value)
        }
    }
}
