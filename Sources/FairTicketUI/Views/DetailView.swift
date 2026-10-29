import SwiftUI
import FairTicketKit

/// Renders the configuration group currently selected in the sidebar.
///
/// The form is generated from the engine's `field_specs`, so a field added on the
/// Python side appears here without a Swift change — and the Python test suite
/// fails if a spec goes missing, which is what keeps the two in step.
struct DetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var ui: UIState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.motionEnabled) private var motionEnabled
    @Binding var showsLogStrip: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    // An anchor above the page, so switching sections can return to the
                    // top: keeping the old offset drops the user into the middle of a
                    // form they have not seen yet.
                    Color.clear
                        .frame(height: 0)
                        .id(Self.topAnchor)

                    VStack(alignment: .leading, spacing: Theme.Space.md) {
                        if ui.selectedSection == .log {
                            LogPageView()
                        } else if model.isRunning {
                            // A live run owns the pane: every field is frozen, so the
                            // form would only repeat what the sidebar already says.
                            LiveRunView()
                        } else if let section = ui.selectedSection {
                            page(for: section)
                        } else {
                            ContentUnavailableView(
                                "选择一个配置分组",
                                systemImage: "sidebar.left",
                                description: Text("左侧选择要编辑的参数分组。")
                            )
                        }
                    }
                    .padding(.horizontal, Theme.Layout.pageInset)
                    .padding(.top, Theme.Space.lg)
                    .padding(.bottom, Theme.Space.xxl)
                    // The design's own column is narrower than the pane.  Letting the
                    // cards run the full width of a 27" display is what makes a form
                    // read as a spreadsheet.
                    .frame(maxWidth: Theme.Layout.contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The page container for anything inserted or removed *within* a
                    // page — today, the captured-ticket card arriving mid-run.  It lives
                    // here because a transition needs an animation in its enclosing
                    // container, and this VStack is the one view that spans the page.
                    .motion(Theme.Motion.snappy, value: model.latestCandidate != nil)
                    .motion(Theme.Motion.snappy, value: ui.showsCartDraft)
                }
                .background(Theme.canvas(scheme))
                .onChange(of: ui.selectedSection) { _, _ in
                    proxy.scrollTo(Self.topAnchor, anchor: .top)
                }
            }

            if showsLogStrip, ui.selectedSection != .log {
                LogStripView(showsLogStrip: $showsLogStrip)
                    // A transition, not just an animation: the strip is inserted and
                    // removed conditionally, and without one the collapse merely
                    // snapped the pane shorter while everything above it jumped.
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // The strip is toggled from the View menu and by switching to the log page, so
        // the animation is attached to the state rather than to any one of those
        // actions.
        .motion(Theme.Motion.snappy, value: showsLogStrip)
        .frame(minWidth: Theme.configMinimumWidth, alignment: .topLeading)
    }

    private static let topAnchor = "page-top"

    // MARK: - Pages

    @ViewBuilder
    private func page(for section: ConfigSection) -> some View {
        PageHeader(
            title: section.headline,
            subtitle: section.lead,
            eyebrow: section.title
        )
        .padding(.bottom, Theme.Space.xs)

        // 行程时间 is the one page the design splits into cards by *field* rather than
        // by backend group: the date, the two times and the mode are three separate
        // decisions, and the engine happens to ship them in one group.
        if section == .trip {
            tripPage()
        } else if section == .passengers {
            passengerPage()
        } else if section == .position {
            positionPage()
        } else {
            ForEach(groups(for: section), id: \.self) { group in
                groupCard(group)
                cartExtras(specsIn(group))
            }
        }

        if section == .advanced {
            intervalCard
            QuietButton("恢复高级参数默认值", systemImage: "arrow.counterclockwise") {
                model.resetAdvancedDefaults()
            }
            .disabled(model.isRunning)
            .padding(.top, Theme.Space.xxs)
        }
    }

    /// 当前查询间隔, lifted out of the collapsed group it also lives in.
    ///
    /// The one parameter worth a slider: it is the knob people actually reach for when a
    /// run is being throttled, and finding it meant opening 查询与热身 first.  The
    /// numeric field inside that group is still there and still writes the same key —
    /// this is a second view of one value, not a second value.
    @ViewBuilder
    private var intervalCard: some View {
        if let spec = spec("query_interval_seconds") {
            let lower = spec.minimum ?? 0.05
            let upper = spec.maximum ?? 60
            let step = spec.step ?? 0.05
            let current = model.double(spec.key)

            Card(
                title: "当前查询间隔",
                titleTint: Theme.accentText(scheme),
                accessory: AnyView(
                    Text(String(format: "%.2f s", current))
                        .font(Theme.data(15, .medium))
                        .foregroundStyle(Theme.textStrong(scheme))
                )
            ) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Slider(
                        value: Binding(
                            get: { min(max(model.double(spec.key), lower), upper) },
                            set: { model.setDouble(spec.key, $0) }
                        ),
                        in: lower...upper,
                        step: step
                    )
                    .tint(Theme.brand)
                    .disabled(model.isRunning)
                    .accessibilityLabel("当前查询间隔")

                    HStack {
                        Text(String(format: "%.2fs", lower))
                            .foregroundStyle(Theme.textTertiary(scheme))
                        Spacer(minLength: Theme.Space.sm)
                        Text(String(format: "%.2fs", current))
                            .foregroundStyle(Theme.accentText(scheme))
                        Spacer(minLength: Theme.Space.sm)
                        Text(String(format: "%.2fs", upper))
                            .foregroundStyle(Theme.textTertiary(scheme))
                    }
                    .font(Theme.data(13))
                }
            }
        }
    }

    /// 乘车人: one card holding the roster, and the page-level notes under it.
    ///
    /// The design merges 姓名 and 票种 into one card because the page's promise is that
    /// the type follows the 12306 record — the override is the exception, so it sits on
    /// the row rather than in a card of its own.
    @ViewBuilder
    private func passengerPage() -> some View {
        let people = model.listItems("passenger_names").count
        let limit = model.capabilities?.maxPassengers ?? 5

        Card(
            title: "本次乘车人",
            accessory: AnyView(
                Text("\(people) / \(limit)")
                    .font(Theme.data(13))
                    .foregroundStyle(
                        people > limit ? Theme.danger(scheme) : Theme.textSecondary(scheme)
                    )
            )
        ) {
            PassengerRosterEditor()
        }

        // The engine's own rule, stated where it applies: 自动提交 is what makes the
        // passenger list required.
        InlineNote(
            text: model.bool("auto_submit")
                ? "若改为「仅监控」模式，乘车人可留空——只查询余票，不会进入下单流程。"
                : "当前为「仅监控」模式：乘车人可以留空——只查询余票，不会进入下单流程。",
            tone: model.bool("auto_submit") ? .warning : .neutral
        )
    }

    /// 座位与铺位: one card, three sub-sections.
    ///
    /// The design keeps all three soft preferences in a single card, split by quiet
    /// sub-labels rather than by card headers — they are all the same kind of thing
    /// (a request the engine submits once and 12306 may refuse), so three cards would
    /// suggest three separate decisions.
    ///
    /// The seat grid itself is deliberately *not* the design's: it keeps the app's own
    /// tile layout, which was judged clearer than the drawing's tick-marked letters.
    @ViewBuilder
    private func positionPage() -> some View {
        Card(title: "座位位置偏好", bodyInset: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if let quiet = spec("quiet_carriage_preference") {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        subLabel("其他偏好")
                        FieldRow(spec: quiet)
                    }
                }

                if let seat = spec("seat_position_preferences") {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        subLabel("座位位置", tint: Theme.accentText(scheme))
                        SeatMapEditor(spec: seat)
                    }
                }

                if let berth = spec("berth_preference") {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        subLabel("铺位数量")
                        Text("仅卧铺车次 · 三项之和须等于乘车人数")
                            .font(Theme.ui(13))
                            .foregroundStyle(Theme.textSecondary(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                        BerthCountEditor(spec: berth)
                    }
                }
            }
        }
    }

    /// Section headings use a consistent weight and ink, with their own reading space.
    private func subLabel(_ text: String, tint: Color? = nil) -> some View {
        Text(text)
            .font(Theme.sectionTitle)
            .foregroundStyle(tint ?? Theme.textStrong(scheme))
            .padding(.top, Theme.Space.xxs)
    }

    /// The trip page, in the design's three cards.
    ///
    /// Keyed off the field *keys*, because the split is the page's own composition
    /// rather than something the backend describes.  If any of them is missing — the
    /// engine renamed a field or moved it to another group — the page falls back to the
    /// generic group renderer instead of drawing nothing, which is the failure mode a
    /// hard-coded layout would otherwise have.
    @ViewBuilder
    private func tripPage() -> some View {
        if spec("train_date") != nil, spec("start_at") != nil,
           spec("stop_at") != nil, spec("auto_submit") != nil {
            tripDateCard
            tripWindowCard
            tripModeCard
            tripSafetyNote
        } else {
            ForEach(groups(for: .trip), id: \.self) { group in
                groupCard(group)
                cartExtras(specsIn(group))
            }
        }
    }

    @ViewBuilder
    private var tripDateCard: some View {
        if let date = spec("train_date") {
            Card(title: "乘车日期", marker: "必填") {
                HStack(alignment: .center, spacing: Theme.Space.md) {
                    FieldRow(spec: date)
                        .frame(maxWidth: 240, alignment: .leading)
                    Text("寒暑假与节假日前建议提前一天配置")
                        .font(Theme.ui(14))
                        .foregroundStyle(Theme.textTertiary(scheme))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var tripWindowCard: some View {
        if let start = spec("start_at"), let stop = spec("stop_at") {
            Card(title: "开始与停止时刻", marker: "可选", markerTint: Theme.textSecondary(scheme)) {
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    FieldRow(spec: start)
                    FieldRow(spec: stop)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var tripModeCard: some View {
        if let mode = spec("auto_submit") {
            Card(title: "任务模式") {
                ModeSelector(
                    autoSubmit: Binding(
                        get: { model.bool(mode.key) },
                        set: { model.setBool(mode.key, $0) }
                    ),
                    enabled: !model.isRunning
                )
            }
        }
    }

    /// The safety note, at the foot of the page rather than inside a card.
    ///
    /// It describes what happens at *the end of a run* — how 停止时刻 interacts with the
    /// server already holding a reservation — which is a page-level consequence of the
    /// two cards above it, not a property of either one.
    private var tripSafetyNote: some View {
        InlineNote(
            text: "到达安全停止时刻后程序会立即停止，且不会尝试后续车次——"
                + "服务端可能已受理订单，请到 12306 待支付订单核对。",
            tone: .neutral
        )
    }

    /// One field's spec, by key.
    private func spec(_ key: String) -> FieldSpec? {
        model.capabilities?.fieldSpecs.first { $0.key == key }
    }

    /// The marker the design puts at a card's trailing edge.
    ///
    /// Only 添加备选's own cards carry one — 必填 there says "the engine cannot build an
    /// entry without this", which is the one place a required marker earns its space.
    /// The other pages' cards are all required or all optional, so a marker on every one
    /// of them would be a column of identical words; the design leaves them clean and so
    /// does this.
    private func marker(for section: ConfigSection, group: String) -> (String, Color?)? {
        let people = model.listItems("passenger_names").count
        let limit = model.capabilities?.maxPassengers ?? 5

        switch section {
        case .passengers:
            // The one number a user needs here: how many of the engine's slots are used.
            // It is not a required/optional marker, it is a count, which is why it lives
            // in the header rather than in the body.
            return ("\(people) / \(limit)", people > limit ? Theme.danger(scheme) : nil)
        case .cart, .trip, .position, .advanced, .log:
            return nil
        }
    }

    /// Header glyph per backend group name — kept for the seat and berth editors, which
    /// still anchor themselves with a mark.
    ///
    /// A rename on the Python side falls back to a generic icon rather than breaking
    /// the layout, because the group's *identity* here is decoration, not behaviour.
    private static func icon(for group: String) -> String {
        switch group {
        case "备选列表": return "cart.fill"
        case "日期与时间": return "calendar"
        case "乘车人与票种": return "person.2.fill"
        case "座位与铺位偏好": return "rectangle.split.3x1.fill"
        case "任务模式": return "bolt.fill"
        case "查询与热身": return "timer"
        case "网络、登录与校时": return "network"
        case "出票等待与诊断": return "waveform.path.ecg"
        default: return "slider.horizontal.3"
        }
    }

    /// Groups each sidebar section owns.
    ///
    /// Resolved from the specs' *keys* rather than hard-coded group names, so a
    /// group renamed on the Python side still lands somewhere.  Anything not claimed
    /// by a dedicated section falls through to 高级参数, which is what stops a newly
    /// added backend field from becoming unreachable in this window.
    private func groups(for section: ConfigSection) -> [String] {
        guard let capabilities = model.capabilities else { return [] }
        if section == .log { return [] }

        if section == .advanced {
            let claimed = ConfigSection.claimedKeys
            return capabilities.groupOrder.filter { group in
                capabilities.specs(inGroup: group).contains { !claimed.contains($0.key) }
            }
        }

        let owned = ConfigSection.keys(for: section)
        return capabilities.groupOrder.filter { group in
            capabilities.specs(inGroup: group).contains { owned.contains($0.key) }
        }
    }

    private func specsIn(_ group: String) -> [FieldSpec] {
        model.capabilities?.specs(inGroup: group) ?? []
    }

    @ViewBuilder
    private func groupCard(_ group: String) -> some View {
        let specs = specsIn(group)
        // 高级参数 is the only page whose every field already has a working default, so
        // it is the only one that opens collapsed.  Fifteen fields presented open read as
        // a page to be worked through; the same fields behind a header read as a place to
        // go only if something is wrong.
        let collapsible = ui.selectedSection == .advanced
        let expanded = !collapsible || ui.expandedAdvancedGroups.contains(group)
        let markerInfo = ui.selectedSection.flatMap { marker(for: $0, group: group) }

        if specs.contains(where: { $0.kind == .cart }) {
            // The cart's entries are cards in their own right, so wrapping them in one
            // more card drew a box around a column of boxes.
            fields(specs, in: group)
        } else {
            Card(
                title: group,
                marker: markerInfo?.0,
                markerTint: markerInfo?.1,
                accessory: collapsible
                    ? AnyView(disclosure(for: group, expanded: expanded, count: specs.count))
                    : nil,
                showsContent: expanded
            ) {
                fields(specs, in: group)
            }
        }
    }

    /// The header control that opens a collapsed group.
    ///
    /// Carries the field count so the collapsed page still says how much sits behind each
    /// header, and the chevron rotates rather than swapping glyph, which is how macOS
    /// spells "this opens".
    private func disclosure(for group: String, expanded: Bool, count: Int) -> some View {
        Button {
            withAnimation(motionEnabled ? Theme.Motion.snappy : nil) {
                if expanded {
                    ui.expandedAdvancedGroups.remove(group)
                } else {
                    ui.expandedAdvancedGroups.insert(group)
                }
            }
        } label: {
            HStack(spacing: 6) {
                CountChip(text: "\(count) 项")
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group)
        .accessibilityValue(expanded ? "已展开" : "已收起")
    }

    /// The fields of one group.  Split out of `groupCard` because the disclosure decides
    /// whether it is built at all.
    @ViewBuilder
    private func fields(_ specs: [FieldSpec], in group: String) -> some View {
        if usesTwoColumnGrid(specs) {
            LazyVGrid(columns: Self.twoColumnGrid, alignment: .leading, spacing: Theme.Space.md) {
                ForEach(specs) { spec in
                    FieldRow(spec: spec)
                }
            }
        } else if specs.contains(where: { $0.key == "train_date" }) {
            dateAndTimeLayout(specs)
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                ForEach(specs) { spec in
                    FieldRow(spec: spec)
                }
            }
        }
    }

    /// 日期与时间, laid out as a grid rather than a column of full-width rows.
    ///
    /// The date and the two optional times are independent of one another, so stacking
    /// them full width left roughly 700pt of nothing to the right of the date field and
    /// of each time stepper, and pushed the page past the fold for no reason.
    ///
    /// Two columns rather than three even though a wide window would take three: the time
    /// controls are ~170pt wide before their toggle, and two columns is the most that still
    /// fits them when the inspector is open on a window near its minimum width.
    @ViewBuilder
    private func dateAndTimeLayout(_ specs: [FieldSpec]) -> some View {
        let rows = [
            ["train_date"],
            ["start_at", "stop_at"],
        ]
        let placed = Set(rows.flatMap { $0 })

        VStack(alignment: .leading, spacing: Theme.Space.md) {
            ForEach(rows, id: \.self) { keys in
                LazyVGrid(columns: Self.twoColumnGrid, alignment: .leading, spacing: Theme.Space.md) {
                    ForEach(keys, id: \.self) { key in
                        if let spec = specs.first(where: { $0.key == key }) {
                            FieldRow(spec: spec)
                        }
                    }
                }
            }

            // Anything the backend adds to this group lands here rather than nowhere.
            ForEach(specs.filter { !placed.contains($0.key) }) { spec in
                FieldRow(spec: spec)
            }
        }
    }

    /// The cart page's own composition: the row that adds to the list, and the engine's
    /// description of what the whole thing would attempt.
    ///
    /// Decided by the spec's *kind*, not by the group's name.  Group names are decoration
    /// everywhere else in this file — a rename falls back to a generic icon — but these
    /// two cards are what makes a cart fillable at all, so a rename on the Python side
    /// must not be able to remove them.  (It did, once: a stale group name silently left
    /// the cart page with no way to add an entry.)
    @ViewBuilder
    private func cartExtras(_ specs: [FieldSpec]) -> some View {
        if specs.contains(where: { $0.kind == .cart }) {
            newEntryButton
            if ui.showsCartDraft {
                CartDraftCard()
                    .transition(Theme.Motion.reveal)
            }
            cartPreview
        }
    }

    /// 新增备选, centred under the entries — the design draws it as a plain word rather
    /// than a chip, because on this page it is not competing with anything: the entries
    /// above it are the primary content and this is the only way onward.
    ///
    /// The composer stays out of the way until it is asked for: with it open the page is
    /// a form again, and the thing a returning user comes back to this page for is the
    /// order of the entries, not the stations they already filled in.
    private var newEntryButton: some View {
        HStack(spacing: Theme.Space.md) {
            Spacer(minLength: 0)
            Button {
                withAnimation(motionEnabled ? Theme.Motion.snappy : nil) {
                    ui.showsCartDraft.toggle()
                }
            } label: {
                Text(ui.showsCartDraft ? "收起填写" : "新增备选")
                    .font(Theme.ui(15))
                    .foregroundStyle(Theme.textSecondary(scheme))
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .help("填写一站一程的详细参数，可批量展开为多条备选")

            Button {
                ui.showsCartManager = true
            } label: {
                Text("管理购物车")
                    .font(Theme.ui(15))
                    .foregroundStyle(Theme.textTertiary(scheme))
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .disabled(model.cartItems.isEmpty)
            .help("以表格调整尝试顺序、编辑或移除某一项")
            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Space.xxs)
    }

    /// The engine's own description of what the cart would attempt.
    ///
    /// Both strings come from the engine, so the form and the start confirmation
    /// describe the same attempt order — and the numbering is the engine's, not a
    /// running count built here.
    @ViewBuilder
    private var cartPreview: some View {
        if let preview = model.preview, preview.cartCount > 0 {
            Card(
                title: "本轮尝试顺序",
                accessory: AnyView(
                    Button("引擎计算") {
                        Task { await model.validate() }
                    }
                    .buttonStyle(.chipAction(height: 24))
                    .disabled(!model.engineState.isReady || model.isRunning)
                    .help("让引擎按当前购物车与席别重新计算尝试顺序")
                )
            ) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    ForEach(Array(previewLines.enumerated()), id: \.element.id) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                            Text(String(format: "%02d", index + 1))
                                .font(Theme.data(13, .medium))
                                .foregroundStyle(
                                    index == 0 ? Theme.accentText(scheme) : Theme.textTertiary(scheme)
                                )
                            Text(line.text)
                                .font(Theme.ui(14))
                                .foregroundStyle(
                                    index == 0 ? Theme.text(scheme) : Theme.textSecondary(scheme)
                                )
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    /// The engine's attempt order, one line per attempt, without its own numbering: the
    /// row's index column carries that, so the first attempt can be the orange one.
    private var previewLines: [PriorityPreviewLine] {
        var occurrences: [String: Int] = [:]
        return (model.preview?.priorityPreview ?? "")
            .split(whereSeparator: \.isNewline)
            .compactMap { source in
                let sourceText = String(source).trimmingCharacters(in: .whitespaces)
                let text = sourceText
                    .replacingOccurrences(of: #"^\s*\d+[\.\)、]?\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return nil }

                let occurrence = occurrences[text, default: 0]
                occurrences[text] = occurrence + 1
                return PriorityPreviewLine(
                    id: "\(text)\u{1F}\(occurrence)",
                    text: text
                )
            }
    }

    /// The desktop form lays the advanced parameters out in two columns; a single
    /// column of ten spin rows would scroll for no reason.  Composite widgets opt
    /// out because they need the full width.
    private func usesTwoColumnGrid(_ specs: [FieldSpec]) -> Bool {
        guard specs.count > 2 else { return false }
        let compact: Set<FieldSpec.Kind> = [.number, .integer, .choice, .toggle]
        return specs.allSatisfy { compact.contains($0.kind) }
    }

    private static let twoColumnGrid = [
        GridItem(.flexible(), spacing: Theme.Space.md, alignment: .topLeading),
        GridItem(.flexible(), spacing: Theme.Space.md, alignment: .topLeading),
    ]
}

/// A displayed attempt line keeps its identity when its position in the preview changes.
private struct PriorityPreviewLine: Identifiable {
    let id: String
    let text: String
}

/// Collapsed log summary pinned under the detail pane.
///
/// The desktop form keeps a fixed-height log card; here the full history lives on
/// its own page and the detail pane carries a glanceable tail, so the form keeps
/// its height while the task is still observable.  It floats as a glass bar rather
/// than sitting flush against the window edge, which is what the current Apple
/// surface language does with auxiliary chrome.
struct LogStripView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var ui: UIState
    @Environment(\.colorScheme) private var scheme
    @Binding var showsLogStrip: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.xs) {
                Text("运行日志")
                    .font(Theme.ui(15, .semibold))
                    .foregroundStyle(Theme.text(scheme))
                CountChip(text: "\(model.logEntries.count) 行")
                Text("引擎输出已脱敏")
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.textTertiary(scheme))
                Spacer(minLength: 0)
                QuietButton("查看全部", systemImage: "arrow.up.forward") {
                    ui.selectedSection = .log
                }
                Button {
                    showsLogStrip = false
                } label: {
                    Image(systemName: "chevron.down").font(Theme.ui(13))
                }
                .buttonStyle(.plain)
                // Names the way back: hiding is the one thing this control does, so
                // the shortcut to undo it is the only discoverable route.
                .help("收起日志（⌥⌘L 重新显示）")
            }
            .padding(.horizontal, Theme.Layout.cardInset)
            .padding(.top, Theme.Space.sm)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(tail) { entry in
                    HStack(alignment: .top, spacing: Theme.Space.xs) {
                        Circle()
                            .fill(color(for: entry.level))
                            .frame(width: 6, height: 6)
                            .padding(.top, 4)
                        Text(entry.text)
                            .font(Theme.monoCaption)
                            .foregroundStyle(
                                entry.level == .debug
                                    ? Theme.textTertiary(scheme)
                                    : Theme.textSecondary(scheme)
                            )
                            .lineLimit(1)
                    }
                }
                if tail.isEmpty {
                    Text("尚无日志。开始任务后会显示已脱敏的运行日志。")
                        .font(Theme.ui(14))
                        .foregroundStyle(Theme.textTertiary(scheme))
                }
            }
            .padding(.horizontal, Theme.Layout.cardInset)
            .padding(.bottom, Theme.Space.sm)
        }
        .cardSurface()
        .padding(.horizontal, Theme.Space.sm)
        .padding(.bottom, Theme.Space.xs)
    }

    private var tail: [LogEntry] {
        Array(model.logEntries.suffix(4))
    }

    private func color(for level: LogEntry.Level) -> Color {
        switch level {
        case .error, .critical: return Theme.danger(scheme)
        case .warning: return Theme.brand
        case .debug: return Theme.textTertiary(scheme)
        case .info: return Theme.textSecondary(scheme)
        }
    }
}
