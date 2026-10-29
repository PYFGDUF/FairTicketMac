import SwiftUI
import FairTicketKit

// MARK: - Seat products

/// One clickable seat product.
///
/// Clickable anywhere in the row, matching the desktop form's hit behaviour.  Shared
/// with the cart's own seat chooser: version 5 has no standalone seat list, so the
/// only place a seat is selected is inside a cart entry — but the control that picks
/// it is the same one, and the labels still come from the engine's seat table.
struct SeatChip: View {
    let label: String
    let selected: Bool
    let toggle: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 7) {
                CheckTile(isOn: selected)
                Text(label)
                    .font(Theme.ui(14))
                    .foregroundStyle(selected ? Theme.text(scheme) : Theme.textSecondary(scheme))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected
                    ? AnyShapeStyle(Theme.brandWash(scheme))
                    : AnyShapeStyle(hovering ? Theme.chipHover(scheme) : Theme.chip(scheme)),
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
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: selected)
        .motion(Theme.Motion.snappy, value: hovering)
        // VoiceOver hears "二等座, 已选" instead of just the glyph and the label.
        .accessibilityLabel(label)
        .accessibilityValue(selected ? "已选" : "未选")
        .accessibilityHint("切换是否尝试该席别")
    }
}

// MARK: - Seat relation map

/// Two relative rows of letters.  The letters are not hard-coded: 一等座 is ACDF and
/// 特等座 is ACF on the same train, and the engine already publishes that table.
struct SeatMapEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.motionEnabled) private var motionEnabled
    let spec: FieldSpec

    private var letters: [String] { model.seatMapLetters() }
    private var passengerCount: Int { model.passengerCountForDisplay() }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            if letters.isEmpty {
                InlineNote(text: "只有在已选择支持 ABCDF 的座席时才启用座位关系图；硬座、软座、无座不会启用。")
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    ForEach([1, 2], id: \.self) { row in
                        seatRow(row)
                    }
                }

                HStack(spacing: Theme.Space.md) {
                    legend(selected: true, text: "已选位置")
                    legend(selected: false, text: "可选")
                    Spacer(minLength: Theme.Space.xs)
                    Text(selectionSummary)
                        .font(Theme.ui(14))
                        .foregroundStyle(Theme.textTertiary(scheme))
                        .lineLimit(1)
                }

                InlineNote(
                    text: "每名乘车人选一格，且格子数须等于乘车人数（当前 \(passengerCount) 人）。"
                        + "前排／后排表示两排的相对位置，不代表行驶方向或排号。"
                )
            }
        }
    }

    /// What the current choice means in the engine's own terms — the pairing rule a
    /// traveller actually recognises ("同侧 A/F"), not the list of letters.
    private var selectionSummary: String {
        let chosen = model.seatPositions()
        guard !chosen.isEmpty else { return "尚未选择位置" }
        return "已选 " + chosen.joined(separator: " · ")
    }

    private func legend(selected: Bool, text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(selected ? Theme.brand : Theme.chip(scheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(selected ? Color.clear : Theme.hairline(scheme), lineWidth: 1)
                )
                .frame(width: 11, height: 11)
            Text(text)
                .font(Theme.ui(14))
                .foregroundStyle(Theme.textSecondary(scheme))
        }
    }

    private func seatRow(_ row: Int) -> some View {
        // The aisle sits before D, matching the 3+2 layout the backend documents.
        let aisleIndex = letters.firstIndex(of: "D") ?? letters.count
        // The backend rejects a second-row choice for a single passenger.
        let rowUsable = row == 1 || passengerCount != 1
        return HStack(spacing: 6) {
            Text("\(row == 1 ? "前排" : "后排") \(row)")
                .font(Theme.ui(14))
                .foregroundStyle(Theme.textTertiary(scheme))
                .frame(width: 48, alignment: .leading)
            ForEach(Array(letters.enumerated()), id: \.element) { index, letter in
                if index == aisleIndex { aisle }
                seatTile(row: row, letter: letter, enabled: rowUsable)
            }
            Spacer(minLength: 0)
        }
    }

    private func seatTile(row: Int, letter: String, enabled: Bool) -> some View {
        let position = "\(row)\(letter)"
        let selected = model.seatPositions().contains(position)
        return Button {
            withAnimation(motionEnabled ? Theme.Motion.snappy : nil) {
                model.toggleSeatPosition(position)
            }
        } label: {
            Text(letter)
                .font(Theme.ui(15, .medium))
                .frame(width: 32, height: 30)
                .background(
                    selected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Theme.chip(scheme)),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                )
                .foregroundStyle(selected ? Theme.onBrand : Theme.textSecondary(scheme))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(
                            selected ? Color.clear : Theme.hairline(scheme),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(enabled ? position : "单人乘车只能选择第一排")
        .accessibilityLabel("\(row == 1 ? "前排" : "后排") \(letter) 座")
        .accessibilityValue(selected ? "已选" : "未选")
    }

    /// The aisle: a dashed gap, so the seat letters read as a car layout rather than
    /// an arbitrary row of buttons.
    private var aisle: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.hairline(scheme))
                .frame(width: 1, height: 30)
        }
        .frame(width: 22)
    }
}

// MARK: - Berth counts

/// Lower / middle / upper counts.  Inactive until a berth product is selected, and
/// in that state the values are kept rather than cleared, matching the desktop form.
struct BerthCountEditor: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var ui: UIState
    let spec: FieldSpec

    private var isDormant: Bool { model.selectedBerthProducts().isEmpty }
    private var passengerCount: Int { model.passengerCountForDisplay() }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            if isDormant {
                InlineNote(text: "未勾选任何卧铺席别时，此处保留为「未启用」：不校验数量，也不会提交。")
                QuietButton("去选择卧铺席别", systemImage: "bed.double") {
                    ui.revealBerthSelection()
                }
            } else {
                let counts = model.berthCounts()
                // A row per berth rather than three columns: the design reads the counts
                // down the page, which is also how a traveller lists them aloud.
                VStack(alignment: .leading, spacing: 6) {
                    BerthCounter(label: "下铺", value: counts.lower) {
                        model.setBerth(lower: $0, middle: counts.middle, upper: counts.upper)
                    }
                    BerthCounter(label: "中铺", value: counts.middle) {
                        model.setBerth(lower: counts.lower, middle: $0, upper: counts.upper)
                    }
                    BerthCounter(label: "上铺", value: counts.upper) {
                        model.setBerth(lower: counts.lower, middle: counts.middle, upper: $0)
                    }
                }
                let sum = counts.lower + counts.middle + counts.upper
                InlineNote(
                    text: sum == passengerCount
                        ? "三项之和 \(sum) 与乘车人数一致。"
                        : "三项之和须等于乘车人数（当前 \(passengerCount) 人，已填 \(sum)）。",
                    tone: sum == passengerCount ? .neutral : .warning
                )
            }
        }
    }
}

/// One berth count: a label, and the stepper the design puts opposite it.
private struct BerthCounter: View {
    let label: String
    let value: Int
    let onChange: (Int) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Text(label)
                .font(Theme.ui(15))
                .foregroundStyle(Theme.textSecondary(scheme))
            Spacer(minLength: Theme.Space.xs)
            HStack(spacing: 0) {
                stepButton("minus", enabled: value > 0) { onChange(max(0, value - 1)) }

                Text("\(value)")
                    .font(Theme.ui(15, .medium))
                    .foregroundStyle(value > 0 ? Theme.accentText(scheme) : Theme.textTertiary(scheme))
                    .contentTransition(.numericText())
                    .frame(width: 34)
                    .motion(Theme.Motion.snappy, value: value)

                stepButton("plus", enabled: value < 5) { onChange(min(5, value + 1)) }
            }
            .frame(height: 28)
            .background(
                Theme.chip(scheme),
                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(Theme.hairline(scheme), lineWidth: 1)
            )
        }
        .padding(.horizontal, Theme.Space.sm)
        .frame(width: 220)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.ui(12, .semibold))
                .frame(width: 26, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Theme.textSecondary(scheme) : Theme.textTertiary(scheme).opacity(0.5))
        .disabled(!enabled)
        .accessibilityLabel(symbol == "minus" ? "减少一个" : "增加一个")
    }
}
