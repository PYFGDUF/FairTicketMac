import SwiftUI
import FairTicketKit

/// The cart as a table: order, route, train, seat, and the three things you can do to a
/// row.
///
/// The cart page's cards are for *reading* the attempt order; this is for *working* it —
/// reordering by drag, editing one entry in place, removing one — which is a different
/// posture and earns its own surface.  Edits land on a local copy and are written back
/// per row, so 取消 closes the table without having changed anything.
struct CartManagerView: View {
    let onClose: () -> Void

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var ui: UIState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.motionEnabled) private var motionEnabled

    @State private var dragging: String?
    /// The entry the inline editor is holding, and where it came from.
    @State private var editing: CartItem?
    @State private var editingIndex: Int?

    private var entries: [CartItem] { model.cartItems }

    /// The table shows four rows and counts the rest, as the design does: the panel is
    /// a quick reorder, and a scroll area inside a modal hides exactly the rows someone
    /// opened it to move.
    private var visibleEntries: [CartItem] { Array(entries.prefix(4)) }

    /// The panel's body height, from what is actually in it: four rows at most, the
    /// "and N more" line, and the editor when one is open.
    private var panelHeight: CGFloat {
        var height: CGFloat = 50 + CGFloat(visibleEntries.count) * 46 + 32
        if entries.count > visibleEntries.count { height += 26 }
        if editing != nil { height += 290 }
        return height
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    table
                    if editing != nil {
                        editor.transition(Theme.Motion.reveal)
                    }
                }
                .padding(Theme.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: panelHeight)
            footer
        }
        .frame(width: 740)
        .background(
            Theme.card(scheme),
            in: RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.22), radius: 30, y: 12)
        .motion(Theme.Motion.snappy, value: editing?.id)
        .motion(Theme.Motion.snappy, value: visibleEntries.map(\.id))
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: Theme.Space.xs) {
                Text("购物车 · 按顺序尝试")
                    .font(Theme.ui(19, .semibold))
                    .foregroundStyle(Theme.textStrong(scheme))
                CountChip(text: "\(entries.count) 项")
                Spacer(minLength: 0)
                Button("新增") {
                    onClose()
                    ui.selectedSection = .cart
                    ui.showsCartDraft = true
                }
                .buttonStyle(.chipAction(height: 28))
                .help("关闭管理表并打开添加备选")
            }
            Text("拖动调整尝试顺序；任意一项出票成功后，其余备选停止。列表顺序即引擎的提交顺序。")
                .font(Theme.ui(14))
                .foregroundStyle(Theme.textSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.top, Theme.Space.lg)
        .padding(.bottom, Theme.Space.sm)
    }

    // MARK: Table

    private var table: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.sm) {
                Text("顺序").frame(width: 44, alignment: .leading)
                Text("路线").frame(maxWidth: .infinity, alignment: .leading)
                Text("车次").frame(width: 92, alignment: .leading)
                Text("席别").frame(width: 76, alignment: .leading)
                Text("操作").frame(width: 76, alignment: .trailing)
            }
            .font(Theme.ui(13, .medium))
            .foregroundStyle(Theme.textTertiary(scheme))
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 9)
            .background(alignment: .bottom) {
                Rectangle().fill(Theme.divider(scheme)).frame(height: 1)
            }

            if entries.isEmpty {
                Text("购物车为空；加入备选后才能启动任务。")
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.textTertiary(scheme))
                    .padding(Theme.Space.md)
            } else {
                VStack(spacing: Theme.Space.xxs) {
                    ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, item in
                        row(index: index, item: item)
                            .transition(Theme.Motion.item)
                            .onDrag {
                                dragging = item.id
                                return NSItemProvider(object: item.id as NSString)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: CartManagerReorderDelegate(
                                    target: item.id,
                                    dragged: { dragging },
                                    move: { source in
                                        guard let source, source != item.id else { return }
                                        withAnimation(motionEnabled ? Theme.Motion.snappy : nil) {
                                            model.moveCartItem(source, to: item.id)
                                        }
                                    },
                                    finish: { dragging = nil }
                                )
                            )
                    }
                }
                .padding(.top, Theme.Space.xxs)

                if entries.count > visibleEntries.count {
                    Text("还有 \(entries.count - visibleEntries.count) 项 · 在购物车页可调整顺序")
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.textTertiary(scheme))
                        .padding(.top, Theme.Space.xs)
                }
            }
        }
        .background(
            Theme.well(scheme),
            in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        )
    }

    private func row(index: Int, item: CartItem) -> some View {
        let isEditing = editing?.id == item.id
        return HStack(spacing: Theme.Space.sm) {
            HStack(spacing: 6) {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .font(Theme.ui(11, .bold))
                    .foregroundStyle(Theme.textTertiary(scheme))
                Text("\(index + 1)")
                    .font(Theme.data(13, .medium))
                    .foregroundStyle(
                        index == 0 ? Theme.accentText(scheme) : Theme.textSecondary(scheme)
                    )
            }
            .frame(width: 44, alignment: .leading)

            Text("\(item.fromStation) → \(item.toStation)")
                .font(Theme.ui(14, .medium))
                .foregroundStyle(Theme.text(scheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.trainScope == CartItem.scopeSpecific ? item.trainCode : "不限车次")
                .font(Theme.data(13, .medium))
                .foregroundStyle(
                    item.trainScope == CartItem.scopeSpecific
                        ? Theme.accentText(scheme)
                        : Theme.textSecondary(scheme)
                )
                .lineLimit(1)
                .frame(width: 92, alignment: .leading)

            Text(item.seatType)
                .font(Theme.ui(14))
                .foregroundStyle(Theme.text(scheme))
                .lineLimit(1)
                .frame(width: 76, alignment: .leading)

            HStack(spacing: Theme.Space.xs) {
                Button("编辑") { beginEditing(index: index, item: item) }
                    .buttonStyle(.plain)
                    .font(Theme.ui(13, .medium))
                    .foregroundStyle(isEditing ? Theme.accentText(scheme) : Theme.textSecondary(scheme))
                Button("删除") { model.removeCartItem(item.id) }
                    .buttonStyle(.plain)
                    .font(Theme.ui(13, .medium))
                    .foregroundStyle(Theme.textTertiary(scheme))
            }
            .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 9)
        .background(
            isEditing ? Theme.brandWash(scheme) : Color.clear,
            in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(isEditing ? Theme.brandEdge(scheme) : Color.clear, lineWidth: 1)
        )
        .opacity(dragging == item.id ? 0.45 : 1)
    }

    // MARK: Editor

    private func beginEditing(index: Int, item: CartItem) {
        editing = item
        editingIndex = index
    }

    @ViewBuilder
    private var editor: some View {
        if let editing, let editingIndex {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                    Text("编辑第 \(editingIndex + 1) 项")
                        .font(Theme.ui(14, .semibold))
                        .foregroundStyle(Theme.accentText(scheme))
                    Text("编辑单项时只能填一个车次；需要多个车次请回到「添加备选」。")
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.textTertiary(scheme))
                    Spacer(minLength: 0)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Theme.Space.md, alignment: .topLeading),
                        GridItem(.flexible(), spacing: Theme.Space.md, alignment: .topLeading),
                    ],
                    spacing: Theme.Space.sm
                ) {
                    stationField("出发站", text: binding(\.fromStation))
                    stationField("到达站", text: binding(\.toStation))
                    scopeField
                    seatField
                }

                if editing.trainScope == CartItem.scopeSpecific {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("车次")
                            .font(Theme.fieldLabel)
                            .foregroundStyle(Theme.textTertiary(scheme))
                        ThemedField("例如 G101", text: binding(\.trainCode))
                    }
                }

                HStack(spacing: Theme.Space.xs) {
                    Button("保存本项") { commit(editing) }
                        .buttonStyle(.brandAction(height: 30))
                        // The hint below promises these two keys, and the panel's footer
                        // owns them otherwise — see `footer`.
                        .keyboardShortcut(.defaultAction)
                    Button("取消编辑") { cancelEditing() }
                        .buttonStyle(.chipAction(height: 30))
                        .keyboardShortcut(.cancelAction)
                    Spacer(minLength: 0)
                    Text("Enter 保存 · Esc 取消")
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.textTertiary(scheme))
                }

                if let duplicate = duplicateOf(editing) {
                    InlineNote(
                        text: "与第 \(duplicate + 1) 项完全相同，未保存重复项目。",
                        tone: .warning
                    )
                }
            }
            .padding(Theme.Space.md)
            .background(
                Theme.well(scheme),
                in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
            )
        }
    }

    private func binding(_ keyPath: WritableKeyPath<CartItem, String>) -> Binding<String> {
        Binding(
            get: { editing?[keyPath: keyPath] ?? "" },
            set: { editing?[keyPath: keyPath] = $0 }
        )
    }

    private func stationField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Theme.fieldLabel)
                .foregroundStyle(Theme.textTertiary(scheme))
            StationField(label: label, placeholder: label, text: text)
        }
    }

    /// The two scopes, labelled as the engine labels them.
    ///
    /// `capabilities.train_scopes` is the authority for both the value and the wording;
    /// typing the Chinese here would let the picker drift from the engine's own vocabulary
    /// the day it renames one.
    private var scopes: [(value: String, label: String)] {
        let declared = model.capabilities?.trainScopes.map { ($0.value, $0.label) } ?? []
        guard !declared.isEmpty else {
            return [
                (CartItem.scopeSpecific, "指定车次"),
                (CartItem.scopeAll, "不限车次"),
            ]
        }
        return declared
    }

    private var scopeField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("车次范围")
                .font(Theme.fieldLabel)
                .foregroundStyle(Theme.textTertiary(scheme))
            Picker(
                "",
                selection: Binding(
                    get: { editing?.trainScope ?? CartItem.scopeAll },
                    set: { editing?.trainScope = $0 }
                )
            ) {
                ForEach(scopes, id: \.value) { scope in
                    Text(scope.label).tag(scope.value)
                }
            }
            .labelsHidden()
        }
    }

    private var seatField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("席别")
                .font(Theme.fieldLabel)
                .foregroundStyle(Theme.textTertiary(scheme))
            Picker(
                "",
                selection: Binding(
                    get: { editing?.seatType ?? "" },
                    set: { editing?.seatType = $0 }
                )
            ) {
                ForEach(seatLabels, id: \.self) { label in
                    Text(label).tag(label)
                }
            }
            .labelsHidden()
        }
    }

    private var seatLabels: [String] {
        guard let capabilities = model.capabilities else { return [] }
        return capabilities.seatGroups.seated + capabilities.seatGroups.berth
    }

    /// The index of another entry this edit would collide with, if any.
    private func duplicateOf(_ item: CartItem) -> Int? {
        entries.firstIndex { $0.id == item.id && $0.id != editing?.id }
            ?? entries.indices.first {
                $0 != (editingIndex ?? -1) && entries[$0].id == item.id
            }
    }

    private func commit(_ item: CartItem) {
        // Located by the identity the row had when the editor opened.  `CartItem.id` is
        // derived from the five fields, so the edited row cannot be found by the *new*
        // value, and the index captured at open time is wrong if a drag reordered the
        // list while the editor was up.
        guard let original = editing?.id else { return }
        var next = entries
        guard let index = next.firstIndex(where: { $0.id == original }) else {
            cancelEditing()
            return
        }
        // The note above the buttons promises a duplicate is not saved.  Until here it
        // only promised.
        guard duplicateOf(item) == nil else { return }
        next[index] = item
        model.setCart(next)
        cancelEditing()
    }

    private func cancelEditing() {
        editing = nil
        editingIndex = nil
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: Theme.Space.xs) {
            Text("购物车不能为空；删除全部备选后无法启动任务。")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.textTertiary(scheme))
            Spacer(minLength: Theme.Space.xs)
            Button("取消") { onClose() }
                .buttonStyle(.chipAction(height: 32))
                // Yielded to the row editor while one is open.  Two `.defaultAction`s in
                // a window is not a tie the toolkit resolves helpfully: the footer won,
                // so Enter closed the panel and threw the edit away under a hint that
                // said Enter saves it.
                .keyboardShortcut(editing == nil ? .cancelAction : nil)
            Button("保存修改") { onClose() }
                .buttonStyle(.brandAction(height: 32))
                .keyboardShortcut(editing == nil ? .defaultAction : nil)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
    }
}

private struct CartManagerReorderDelegate: DropDelegate {
    let target: String
    let dragged: () -> String?
    let move: (String?) -> Void
    let finish: () -> Void

    func dropEntered(info: DropInfo) { move(dragged()) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        finish()
        return true
    }
}
