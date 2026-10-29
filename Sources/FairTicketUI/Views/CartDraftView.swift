import SwiftUI
import FairTicketKit

// MARK: - The「添加备选」composer

/// The page for composing one alternative — the design's own screen for it.
///
/// The design draws this as a page rather than a row: an eyebrow, a title that says what
/// the four inputs have in common, then one card per decision — 路线, 车次范围, 席别 —
/// and a fourth that shows what the first three will produce.  The composer is a page
/// because the expansion rule is the whole point: a route with two train codes and two
/// seats is four entries, and the user has to be able to see that before committing.
///
/// The expansion itself is the engine's rule and lives in `cartDraftEntries()`; this view
/// only presents it.  Nothing here decides which entries get made.
struct CartDraftCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var ui: UIState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.motionEnabled) private var motionEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header
            routeCard
            scopeCard
            seatCard
            previewCard
            actionBar
        }
    }

    // MARK: - Page heading

    /// The page states what the four inputs have in common, because that is the part
    /// that is not obvious: they are not four independent settings, they are one
    /// alternative that multiplies.
    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("添加备选")
                .font(Theme.eyebrow)
                .foregroundStyle(Theme.accentText(scheme))
            Text("填写一项备选的详细参数")
                .font(Theme.pageTitle)
                .foregroundStyle(Theme.text(scheme))
            Text("出发站、到达站、车次范围、车次与席别共同决定一项备选；"
                 + "多车次与多席别会自动展开为多条。")
                .font(Theme.pageLead)
                .foregroundStyle(Theme.textSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 路线

    private var routeCard: some View {
        Card(title: "路线", marker: "必填") {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack(alignment: .bottom, spacing: Theme.Space.sm) {
                    labelled("出发站") {
                        StationField(label: "出发站", placeholder: "例如：北京南", text: $model.cartDraft.fromStation)
                    }
                    Button { model.swapDraftStations() } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(Theme.ui(14, .semibold))
                            .frame(width: Theme.Control.height, height: Theme.Control.height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .foregroundStyle(Theme.textSecondary(scheme))
                    .background(Theme.chip(scheme), in: RoundedRectangle(cornerRadius: Theme.Control.radius))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Control.radius)
                            .strokeBorder(Theme.hairline(scheme), lineWidth: 1)
                    }
                    .help("交换出发站和到达站")
                    .accessibilityLabel("交换出发站和到达站")
                    labelled("到达站") {
                        StationField(label: "到达站", placeholder: "例如：上海虹桥", text: $model.cartDraft.toStation)
                    }
                }
                HStack(spacing: Theme.Space.sm) {
                    if model.isUpdatingStations {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel("正在更新站点列表")
                    }
                    Button("更新站点") { Task { await model.updateStations() } }
                        .buttonStyle(.chipAction(height: Theme.Control.height))
                        .disabled(model.isRunning || model.isUpdatingStations)
                        .help("手动从 12306 获取最新站点列表；程序启动时不会自动联网")
                    Text(model.isRunning ? "任务运行中暂停更新" : "手动更新本地站点列表")
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.textSecondary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - 车次范围

    /// Two panels rather than a menu, because the choice changes what the rest of the
    /// card means: 指定车次 needs a code list, 不限车次 does not.
    private var scopeCard: some View {
        Card(title: "车次范围", marker: "必填") {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("不限车次：接受这一站对的所有列车，但仅购买已加入购物车的席别")
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.textSecondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Space.xs) {
                    scopeOption(
                        CartItem.scopeSpecific,
                        title: "指定车次",
                        detail: "只尝试列出车次的余票"
                    )
                    scopeOption(
                        CartItem.scopeAll,
                        title: "不限车次",
                        detail: "接受这一站对的任意列车"
                    )
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("指定车次")
                        .font(Theme.fieldLabel)
                        .foregroundStyle(Theme.textSecondary(scheme))
                    TrainCodeField(text: $model.cartDraft.trainCode)
                        .disabled(model.cartDraft.trainScope != CartItem.scopeSpecific)
                        .opacity(model.cartDraft.trainScope == CartItem.scopeSpecific ? 1 : 0.45)
                        .motion(Theme.Motion.snappy, value: model.cartDraft.trainScope)
                    Text("支持中英文逗号、分号、顿号与换行分隔；已填写则须识别每个车次")
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.textTertiary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func scopeOption(_ value: String, title: String, detail: String) -> some View {
        let selected = model.cartDraft.trainScope == value
        return Button {
            model.cartDraft.trainScope = value
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.ui(15, .semibold))
                    .foregroundStyle(selected ? Theme.accentText(scheme) : Theme.textSecondary(scheme))
                Text(detail)
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.textTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 10)
            .background(
                selected ? Theme.brandWash(scheme) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .motion(Theme.Motion.snappy, value: selected)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - 席别

    /// Both families always shown, each with its own count.  A seat that is not in the
    /// cart cannot be picked, but the row still appears so the user can see it exists —
    /// it is the berth editor downstream that stays dormant, not this list.
    private var seatCard: some View {
        Card(
            title: "席别",
            marker: "必填",
            accessory: AnyView(
                Text("可多选，勾选顺序即为候选顺序")
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.textTertiary(scheme))
            )
        ) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                ForEach([SeatGroup.seated, SeatGroup.berth], id: \.name) { group in
                    let labels = seatLabels(for: group)
                    let chosen = labels.filter { model.cartDraft.seatTypes.contains($0) }.count
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(group.name)
                                .font(Theme.ui(15, .semibold))
                                .foregroundStyle(Theme.text(scheme))
                            Text("已选 \(chosen)")
                                .font(Theme.ui(14))
                                .foregroundStyle(
                                    chosen > 0 ? Theme.accentText(scheme) : Theme.textTertiary(scheme)
                                )
                        }
                        FlowRow(spacing: 8) {
                            ForEach(labels, id: \.self) { label in
                                seatChip(label)
                            }
                        }
                    }
                }
            }
        }
    }

    private func seatLabels(for group: SeatGroup) -> [String] {
        guard let capabilities = model.capabilities else { return [] }
        return group == .seated ? capabilities.seatGroups.seated : capabilities.seatGroups.berth
    }

    /// A seat chip, carrying its position in the selection.
    ///
    /// The number is the candidate order the engine will use, so it is shown inside the
    /// chip rather than as a separate list: clicking in a different order changes the
    /// run, and the numbers are the only place that shows it.
    private func seatChip(_ label: String) -> some View {
        let order = model.cartDraft.seatTypes.firstIndex(of: label)
        let selected = order != nil
        return Button {
            model.toggleDraftSeat(label)
        } label: {
            HStack(spacing: 7) {
                Text(label)
                    .font(Theme.ui(15))
                if let order {
                    Text("\(order + 1)")
                        .font(Theme.data(14, .medium))
                        .transition(Theme.Motion.item)
                }
            }
            .foregroundStyle(selected ? Theme.accentText(scheme) : Theme.text(scheme))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                selected ? Theme.brandWash(scheme) : Theme.chip(scheme),
                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(
                        selected ? Theme.brandEdge(scheme) : Theme.hairline(scheme),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .motion(Theme.Motion.snappy, value: selected)
        .accessibilityLabel(label)
        .accessibilityValue(order.map { "第 \($0 + 1) 个候选" } ?? "未选")
    }

    // MARK: - 将加入的备选

    /// What the three cards above produce, before anything is committed.
    ///
    /// This is the card that makes the page worth being a page: the multiplication
    /// happens somewhere the user cannot see, so the result is drawn back at them.
    @ViewBuilder
    private var previewCard: some View {
        let entries = model.cartDraftEntries()
        let pending = model.pendingCartAdditions()
        let duplicates = entries.count - pending.count
        let trains = model.draftTrainCodes.count
        let seats = model.cartDraft.seatTypes.count

        Card(
            title: "将加入的备选",
            accessory: AnyView(
                HStack(spacing: Theme.Space.xs) {
                    if trains > 0 && seats > 0 {
                        CountChip(text: "\(trains) 车次 × \(seats) 席别 = \(entries.count) 项")
                    }
                    Text("按席别顺序展开，同席别内按车次排序" + (duplicates > 0 ? " · 其中 \(duplicates) 项与购物车完全重复" : ""))
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.textTertiary(scheme))
                }
            )
        ) {
            if entries.isEmpty {
                Text("填好出发站、到达站、车次与席别后，这里会列出将要加入的备选。")
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.textTertiary(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Space.sm)
            } else {
                LazyVGrid(columns: Self.previewColumns, alignment: .leading, spacing: 8) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, item in
                        previewRow(index: index, item: item, isDuplicate: !pending.contains(item))
                    }
                }
            }
        }
    }

    private static let previewColumns = [
        GridItem(.flexible(), spacing: 10, alignment: .leading),
        GridItem(.flexible(), spacing: 10, alignment: .leading),
    ]

    private func previewRow(index: Int, item: CartItem, isDuplicate: Bool) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Text("\(index + 1)")
                .font(Theme.data(14, .medium))
                .foregroundStyle(isDuplicate ? Theme.textTertiary(scheme) : Theme.accentText(scheme))
                .frame(width: 16, alignment: .leading)
            Text("\(item.fromStation) → \(item.toStation)")
                .font(Theme.ui(14))
                .foregroundStyle(isDuplicate ? Theme.textTertiary(scheme) : Theme.text(scheme))
                .lineLimit(1)
            Spacer(minLength: 6)
            if item.trainScope == CartItem.scopeSpecific {
                Text(item.trainCode)
                    .font(Theme.data(14, .medium))
                    .foregroundStyle(isDuplicate ? Theme.textTertiary(scheme) : Theme.accentText(scheme))
            }
            Text(item.seatType)
                .font(Theme.ui(14))
                .foregroundStyle(isDuplicate ? Theme.textTertiary(scheme) : Theme.text(scheme))
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.chip(scheme),
            in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        )
        .help(isDuplicate ? "与购物车中已有的一项完全相同，加入时会被跳过" : "")
    }

    // MARK: - 操作

    private var actionBar: some View {
        HStack(spacing: Theme.Space.sm) {
            // 预览 asks the engine to describe the attempt order — the same call the
            // cart page's 引擎计算 makes, offered here because this is where the draft
            // is being shaped.
            Button("预览") {
                Task { await model.validate() }
            }
            .buttonStyle(.chipAction(height: 34))
            .disabled(!model.engineState.isReady || model.isRunning)
            .help("让引擎按当前购物车重新计算尝试顺序")

            Spacer(minLength: 0)

            Button("清空") {
                model.clearCartDraft()
            }
            .buttonStyle(.chipAction(height: 34))
            .disabled(isDraftEmpty)
            .help("清空这一页填写的内容")

            let count = model.pendingCartAdditions().count
            Button(count > 0 ? "加入购物车（\(count) 项）" : "加入购物车") {
                add()
            }
            .buttonStyle(.brandAction(height: 34))
            .disabled(count == 0)
            .help(
                count == 0
                    ? "填写路线与席别后才能加入"
                    : "把这一页展开出的 \(count) 项按顺序追加到购物车末尾"
            )
        }
        .padding(.top, Theme.Space.xxs)
    }

    private var isDraftEmpty: Bool {
        let draft = model.cartDraft
        return draft.fromStation.isEmpty
            && draft.toStation.isEmpty
            && draft.trainCode.isEmpty
            && draft.seatTypes.isEmpty
    }

    /// Add, then close the composer: the entries are now visible in the list above, which
    /// is what the user came here to change.
    private func add() {
        guard model.commitCartDraft() else { return }
        withAnimation(motionEnabled ? Theme.Motion.snappy : nil) {
            ui.showsCartDraft = false
        }
    }

    // MARK: - Shared bits

    private func labelled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.fieldLabel)
                .foregroundStyle(Theme.textSecondary(scheme))
            content()
        }
        .frame(maxWidth: .infinity)
    }


}

// MARK: - Train code field

/// The 指定车次 input: each code becomes a chip, and the field beside them takes the next.
///
/// Chips rather than a comma-separated string because the codes are a *list* the engine
/// reads positionally — "G101 G105" and "G105 G101" are different runs, and a text field
/// hides that behind punctuation.  The string is still what gets stored; this is a view
/// over it, not a second source of truth.
struct TrainCodeField: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        let codes = model.draftTrainCodes
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            TextField("例如：G103，G105", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.data(15))
                .focused($focused)
                .fieldChrome(isFocused: focused, supportsFocus: true)
                .accessibilityLabel("指定车次")
            if !codes.isEmpty {
                HStack(alignment: .top, spacing: Theme.Space.xs) {
                    Text("已识别")
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.textSecondary(scheme))
                        .padding(.top, 3)
                    FlowRow(spacing: 6, lineSpacing: 6) {
                        ForEach(codes, id: \.self) { code in chip(code) }
                    }
                }
            }
        }
    }

    private func chip(_ code: String) -> some View {
        HStack(spacing: 5) {
            Text(code)
                .font(Theme.data(14, .medium))
            Button {
                model.removeDraftTrainCode(code)
            } label: {
                Image(systemName: "xmark")
                    .font(Theme.ui(11, .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("移除车次 \(code)")
        }
        .foregroundStyle(Theme.text(scheme))
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            Theme.chipHover(scheme),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }
}

// MARK: - Flow row

/// Lays children out left to right, wrapping to the next line when it runs out of room.
///
/// `HStack` cannot wrap and `LazyVGrid` forces equal columns, which a chip row must not
/// have — 商务座 is narrower than 高级软卧, and a grid would leave a gap after each one.
/// The design draws the seat rows and the code list as chips that pack.
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
