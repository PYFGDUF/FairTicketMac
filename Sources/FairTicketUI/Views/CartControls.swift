import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FairTicketKit

// MARK: - The ordered cart

/// The cart entries in attempt order: the page's main object.
///
/// Version 5 of the engine has no separate station pair, train list or seat list —
/// all of it lives inside `cart_items`, and the list order *is* the attempt order
/// (any entry that produces a ticket ends the run).  So this one control replaces
/// the old 行程与乘车人 station row, 车次范围 and 席别与优先级 pages, and it is
/// deliberately a list rather than a sentence: the engine's own wording for the same
/// cart is shown underneath, from `preview.cartRows`.
struct CartEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.motionEnabled) private var motionEnabled
    let spec: FieldSpec

    @State private var dragging: String?

    private var entries: [CartItem] { model.cartItems }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            if entries.isEmpty {
                emptyState
                    .transition(.opacity)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, item in
                    entryRow(index: index, item: item)
                        .transition(Theme.Motion.item)
                        .onDrag {
                            dragging = item.id
                            return NSItemProvider(object: item.id as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: CartReorderDelegate(
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

            // The engine reports every cart problem in one message, one per line, so the note is
            // shown whether or not the cart has entries — an empty cart is its own error.
            if let message = model.visibleFieldError(spec.key) {
                FieldErrorNote(title: "购物车", message: message)
            }
        }
        // Observe identity and order only: typing in a cart editor must not animate
        // every field, while add/remove/reorder all share the same short transition.
        .motion(Theme.Motion.snappy, value: entries.map(\.id))
    }

    /// The empty cart.  A dashed outline rather than a card: it has to read as a slot to
    /// be filled, not as an entry that happens to say nothing.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("尚未加入备选")
                .font(Theme.ui(15, .medium))
                .foregroundStyle(Theme.textSecondary(scheme))
            Text("至少加入一个，任务才知道要抢哪一趟车。")
                .font(Theme.ui(14))
                .foregroundStyle(Theme.textTertiary(scheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.card(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(
                    Theme.hairline(scheme),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
    }
    /// One row, with the reorder actions for its position.
    ///
    /// Built here rather than inline in the `ForEach`: three optional closures inside the
    /// row's argument list pushed the type checker past its limit, which is the same
    /// signal to extract a subview that `swiftui-expert-skill` gives for view bodies.
    private func entryRow(index: Int, item: CartItem) -> CartEntryRow {
        var onMoveToTop: (() -> Void)?
        var onMoveUp: (() -> Void)?
        var onMoveDown: (() -> Void)?
        if index > 0 {
            onMoveToTop = { move(item, to: entries.first) }
            onMoveUp = { move(item, to: entries[index - 1]) }
        }
        if index < entries.count - 1 {
            onMoveDown = { move(item, to: entries[index + 1]) }
        }
        return CartEntryRow(
            index: index + 1,
            item: item,
            onRemove: {
                withAnimation(motionEnabled ? Theme.Motion.snappy : nil) {
                    model.removeCartItem(item.id)
                }
            },
            isDragging: dragging == item.id,
            onMoveToTop: onMoveToTop,
            onMoveUp: onMoveUp,
            onMoveDown: onMoveDown
        )
    }

    /// Reordering, from either the drag or the row's context menu, so both animate alike.
    private func move(_ item: CartItem, to target: CartItem?) {
        guard let target, target.id != item.id else { return }
        withAnimation(motionEnabled ? Theme.Motion.snappy : nil) {
            model.moveCartItem(item.id, to: target.id)
        }
    }
}

/// One cart entry, as the design draws it: a card whose header is the route and whose
/// body is the three facts that describe the attempt.
///
/// Structured rather than a formatted sentence — the engine's own wording for the whole
/// cart arrives separately, and a second locally-built sentence is exactly how the two
/// would drift apart.  The fields are labelled the way the design labels them, so the
/// card can be read without knowing which backend key feeds which cell.
private struct CartEntryRow: View {
    let index: Int
    let item: CartItem
    let onRemove: () -> Void
    /// True while this row is the one being dragged.
    var isDragging = false
    /// Nil when the entry is already at that end of the list, so the menu never offers a
    /// move that would do nothing.
    var onMoveToTop: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(Theme.divider(scheme))
                .frame(height: 1)
            facts
        }
        .cardSurface()
        // The dragged row lifts out of the list: dimmed and pulled back, so which entry
        // is in your hand is legible while the others reorder underneath it.
        .opacity(isDragging ? 0.45 : 1)
        .scaleEffect(isDragging ? 0.985 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.22 : 0), radius: 10, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(
                    hovering ? Theme.brandEdge(scheme) : Color.clear,
                    lineWidth: 1
                )
        )
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isDragging)
        .contextMenu { menuItems }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            SequenceBadge(value: index, emphasised: index == 1)

            Text(item.fromStation.isEmpty ? "未填写" : item.fromStation)
                .font(Theme.valueStrong)
                .foregroundStyle(Theme.textStrong(scheme))
            Image(systemName: "arrow.right")
                .font(Theme.ui(13, .semibold))
                .foregroundStyle(Theme.textTertiary(scheme))
            Text(item.toStation.isEmpty ? "未填写" : item.toStation)
                .font(Theme.valueStrong)
                .foregroundStyle(Theme.textStrong(scheme))

            // Only for the entries that are constrained: a 不限车次 entry says so here and
            // nowhere else, and repeating "指定车次" on the one that names a train would
            // be labelling the absence of a label.
            if item.trainScope != CartItem.scopeSpecific {
                Text(item.scopeLabel)
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.textSecondary(scheme))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.chip(scheme), in: Capsule())
            }

            Spacer(minLength: Theme.Space.xs)

            if item.trainScope == CartItem.scopeSpecific, !item.trainCode.isEmpty {
                Text(item.trainCode)
                    .font(Theme.data(14, .semibold))
                    .foregroundStyle(Theme.text(scheme))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Theme.chip(scheme), in: Capsule())
            }

            if !item.isComplete {
                Text("不完整")
                    .font(Theme.ui(14, .medium))
                    .foregroundStyle(Theme.accentText(scheme))
            }

            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(Theme.ui(15, .semibold))
                    .foregroundStyle(Theme.textTertiary(scheme))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0.6)
            .help("这一项的操作")
        }
        .padding(.horizontal, Theme.Layout.cardInset)
        .padding(.vertical, 13)
    }

    // MARK: Facts

    private var facts: some View {
        HStack(alignment: .top, spacing: Theme.Space.xl) {
            fact("席别优先级", item.seatType.isEmpty ? "未选席别" : item.seatType)
            fact("车次范围", item.trainScope == CartItem.scopeSpecific ? "指定车次" : item.scopeLabel)
            // Only when there is a code to show: an entry that accepts any train has
            // nothing to put here, and a cell reading 不限 beside a cell already reading
            // 不限车次 is one fact printed twice.
            if item.trainScope == CartItem.scopeSpecific {
                fact("车次", item.trainCode.isEmpty ? "未指定" : item.trainCode, mono: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Layout.cardInset)
    }

    private func fact(_ label: String, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(Theme.fieldLabel)
                .foregroundStyle(Theme.textTertiary(scheme))
            Text(value)
                .font(mono ? Theme.data(15) : Theme.value)
                .foregroundStyle(Theme.text(scheme))
                .lineLimit(1)
        }
        .frame(minWidth: 96, alignment: .leading)
    }

    // MARK: Menu

    @ViewBuilder
    private var menuItems: some View {
        if let onMoveToTop {
            Button("移到最前") { onMoveToTop() }
        }
        if let onMoveUp {
            Button("上移一位") { onMoveUp() }
        }
        if let onMoveDown {
            Button("下移一位") { onMoveDown() }
        }
        if onMoveToTop != nil || onMoveUp != nil || onMoveDown != nil {
            Divider()
        }
        Button("复制这一项行程") { copyItinerary() }
        Divider()
        Button("从购物车移除", role: .destructive) { onRemove() }
    }

    /// The row's own words, so what lands on the pasteboard is what the row says.
    private func copyItinerary() {
        let from = item.fromStation.isEmpty ? "未填写" : item.fromStation
        let to = item.toStation.isEmpty ? "未填写" : item.toStation
        let train = item.trainScope == CartItem.scopeSpecific
            ? (item.trainCode.isEmpty ? "未指定车次" : item.trainCode)
            : item.scopeLabel
        let seat = item.seatType.isEmpty ? "未选席别" : item.seatType
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("\(from) → \(to) · \(train) · \(seat)", forType: .string)
    }
}

private struct CartReorderDelegate: DropDelegate {
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



// MARK: - Shared error note

/// The red mark `FieldRow` puts under a control, reused by the composite editors
/// that draw their own layout.  The engine's message is reproduced verbatim,
/// line breaks included, because one message can carry one problem per cart entry.
struct FieldErrorNote: View {
    let title: String
    let message: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Theme.danger(scheme))

            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Theme.danger(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, Theme.Space.xxs)
        .background(
            Theme.danger(scheme).opacity(scheme == .dark ? 0.16 : 0.08),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }
}
