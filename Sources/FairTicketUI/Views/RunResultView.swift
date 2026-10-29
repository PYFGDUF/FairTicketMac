import AppKit
import SwiftUI
import FairTicketKit

/// The account of a finished run, floating over the window.
///
/// The design puts this in a modal panel rather than in the status column because it is
/// the app's rarest and most consequential screen: either a ticket was grabbed and has
/// to be paid for within the hour, or the engine refused to continue because the server
/// may already hold the reservation.  Both need the user's full attention once, and
/// neither belongs in a column they are supposed to be able to ignore.
///
/// Drawn as an overlay rather than presented as a sheet: a sheet is its own window, so
/// it cannot be captured in a screenshot of the main window — and this panel is reviewed
/// far more often than it is reached for real.
struct RunResultView: View {
    let outcome: RunOutcome
    let onClose: () -> Void
    let onOpenOrders: () -> Void
    let onAdjust: () -> Void

    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.motionEnabled) private var motionEnabled
    @State private var successAppeared = false

    var body: some View {
        ViewThatFits(in: .vertical) {
            panelContents.fixedSize(horizontal: false, vertical: true)
            ScrollView { panelContents }
                .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: 580)
        .background(
            Theme.card(scheme),
            in: RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.22), radius: 30, y: 12)
        .onAppear {
            guard outcome.succeeded, motionEnabled else { return }
            withAnimation(Theme.Motion.bouncy) { successAppeared = true }
        }
    }

    private var panelContents: some View {
        VStack(spacing: 0) {
            identity
            facts
                .padding(.horizontal, 20)
                .padding(.top, 20)
            counters
                .padding(.horizontal, 20)
                .padding(.top, Theme.Space.md)
            if !reminder.isEmpty { reminderRow }
            footer
        }
    }

    // MARK: Identity

    /// Whether the run's end reads as an achievement, a caution or neither.
    private var tint: Color {
        if outcome.succeeded { return Theme.success(scheme) }
        if outcome.safeStop { return Theme.accentText(scheme) }
        return outcome.wasStoppedByUser ? Theme.textSecondary(scheme) : Theme.danger(scheme)
    }

    private var identity: some View {
        VStack(spacing: 0) {
            // A solid plate with a white glyph, as the design draws it: at this size a
            // tinted wash reads as a disabled button, and this is the one mark in the
            // window that has to be legible from across the room.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint)
                .overlay(
                    Image(systemName: resultGlyph)
                        .font(Theme.ui(20, .bold))
                        .foregroundStyle(scheme == .dark ? Color(hex: 0x10130F) : Color.white)
                )
                .frame(width: 44, height: 44)
                // One small settling motion for success. Warnings and failures keep
                // a steady mark so the outcome remains easy to read.
                .scaleEffect(outcome.succeeded && motionEnabled && !successAppeared ? 0.9 : 1)

            Text(RunOutcomePresentation.title(outcome))
                .font(Theme.ui(22, .semibold))
                .foregroundStyle(Theme.textStrong(scheme))
                .padding(.top, 12)

            // Said in the outcome's own lightened colour, as the design does: this line
            // is the summary of what happened, not a second helping of body text.
            Text(headline)
                .font(Theme.ui(14))
                .foregroundStyle(headlineTint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.horizontal, Theme.Space.lg)
        }
        .padding(.top, Theme.Space.xl)
        .padding(.bottom, Theme.Space.lg)
        .frame(maxWidth: .infinity)
        .background(Theme.outcomeAtmosphere(for: scheme, succeeded: outcome.succeeded))
    }

    private var headlineTint: Color {
        if outcome.succeeded { return Theme.successText(scheme) }
        if outcome.safeStop || outcome.wasStoppedByUser { return Theme.brandText(scheme) }
        return Theme.textSecondary(scheme)
    }

    /// The panel's own glyph.  Separate from `RunOutcomePresentation.mark`, which picks
    /// an SF Symbol for the *inspector's* 15pt row: a seal reads as a ticket stamp at
    /// 15pt, but at 54pt the design's plain tick is what says "done".
    private var resultGlyph: String {
        if outcome.succeeded { return "checkmark" }
        if outcome.safeStop { return "exclamationmark" }
        if outcome.wasStoppedByUser { return "stop.fill" }
        return "exclamationmark"
    }

    private var headline: String {
        if outcome.succeeded {
            return "请前往 12306「待支付订单」完成核销与支付"
        }
        if outcome.safeStop {
            return "出票状态无法确认，任务已停止以避免重复下单"
        }
        if outcome.wasStoppedByUser {
            return "任务已按你的要求停止"
        }
        return outcome.message.isEmpty ? "本轮任务已结束" : outcome.message
    }

    // MARK: Facts

    /// Four facts, in the design's order: why it stopped, what was configured, who was
    /// in it, and whether anything is waiting to be paid.
    ///
    /// The middle two are labelled for what they are.  The engine's per-entry attempts
    /// arrive on `cart_item` frames during the run, and the roster it used arrives on
    /// `passengers`; this panel is drawn from the *settings*, so it says 备选 and 乘车人
    /// rather than claiming a run-time account it does not have.
    private var facts: some View {
        VStack(spacing: 0) {
            factRow("结束原因", endReason)
            rule
            factRow("备选车次", attemptedTrains)
            rule
            factRow("乘车人", passengerLine)
            rule
            if let orderID = model.orderID, outcome.succeeded {
                factRow("订单号", orderID, mono: true)
                rule
            }
            factRow("订单状态", orderState, tinted: true)
        }
        .background(
            Theme.well(scheme),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private var rule: some View {
        Rectangle()
            .fill(Theme.divider(scheme))
            .frame(height: 1)
            .padding(.leading, Theme.Space.sm)
    }

    private func factRow(_ label: String, _ value: String, tinted: Bool = false, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
            Text(label)
                .font(Theme.ui(14))
                .foregroundStyle(Theme.textTertiary(scheme))
                .frame(width: 66, alignment: .leading)
            Text(value)
                .font(mono ? Theme.data(14, .medium) : Theme.ui(15, .medium))
                .foregroundStyle(tinted ? Theme.accentText(scheme) : Theme.textStrong(scheme))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 11)
    }

    /// The engine's own words for why the run ended; a safe stop is its own reason.
    private var endReason: String {
        if outcome.safeStop { return "到达安全停止时刻" }
        if outcome.wasStoppedByUser { return "用户手动停止" }
        return outcome.message.isEmpty ? "任务正常结束" : outcome.message
    }

    /// The train codes the engine was working through, in order and without repeats.
    private var attemptedTrains: String {
        var codes: [String] = []
        for item in model.cartItems where item.trainScope == CartItem.scopeSpecific {
            let code = item.trainCode.trimmingCharacters(in: .whitespaces)
            if !code.isEmpty, !codes.contains(code) { codes.append(code) }
        }
        return codes.isEmpty ? "不限车次" : codes.joined(separator: " · ")
    }

    private var passengerLine: String {
        let people = model.listItems("passenger_names")
        return people.isEmpty ? "未填写（仅监控）" : people.joined(separator: "、")
    }

    private var orderState: String {
        if outcome.succeeded { return "已提交 · 待支付" }
        if outcome.safeStop { return "状态未知 · 请在 12306 核对" }
        return "无待支付订单 · 未提交"
    }

    // MARK: Counters

    /// The run's own numbers.
    ///
    /// 本轮用时 and 查询次数 are measured here; the third slot shows how many alternatives
    /// the attempt covered, because the engine reports the most recent candidate rather
    /// than a running total — a "捕获余票 N 次" counter would have to be invented, and
    /// this panel is the one place where an invented number would be read as a fact.
    private var counters: some View {
        HStack(spacing: 0) {
            counter("本轮用时", durationSeconds, unit: model.lastRunDuration == nil ? "" : "s")
            counter("查询次数", "\(model.queryCount)", unit: "次")
            counter("备选", "\(model.cartItems.count)", unit: "个")
        }
    }

    private var durationSeconds: String {
        guard let seconds = model.lastRunDuration else { return "—" }
        return String(format: "%.0f", seconds)
    }

    private func counter(_ name: String, _ value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name)
                .font(Theme.fieldLabel)
                .foregroundStyle(Theme.textTertiary(scheme))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Theme.data(16, .semibold))
                    .foregroundStyle(Theme.textStrong(scheme))
                Text(unit)
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.textTertiary(scheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Reminder

    private var reminder: String {
        if outcome.succeeded {
            return "订单保留时间有限，请尽快在 12306 完成支付，逾期未支付将自动取消。"
        }
        if outcome.safeStop {
            return "服务端可能已受理这笔订单。请先到 12306 待支付订单核对，再决定是否重试。"
        }
        if outcome.wasStoppedByUser {
            // The engine's own distinction: stopping after 排队 ended the *status poll*,
            // not the order the server may already hold — so this points at the official
            // order page rather than promising that nothing is in flight.
            return "停止只结束了本机的查询；若订单已提交，请到 12306 待支付订单核对。"
        }
        return model.cartItems.isEmpty
            ? "购物车为空，本轮没有可尝试的备选。"
            : "本轮未捕获余票，未提交任何订单。可调整备选车次或时间窗后重试。"
    }

    private var reminderRow: some View {
        HStack(alignment: .center, spacing: Theme.Space.sm) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tint)
                .frame(width: 16, height: 16)
                .overlay(
                    Image(systemName: outcome.succeeded ? "checkmark" : "exclamationmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(scheme == .dark ? Color(hex: 0x1A0E02) : Color.white)
                )
            Text(reminder)
                .font(Theme.ui(14))
                .foregroundStyle(headlineTint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            outcome.succeeded ? Theme.successWash(scheme) : Theme.brandWash(scheme)
        )
        .padding(.top, Theme.Space.md)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("可在本窗口继续查看完整运行日志")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.textTertiary(scheme))
            HStack(spacing: Theme.Space.xs) {
                Spacer(minLength: Theme.Space.xs)
                Button("关闭") { onClose() }
                    .buttonStyle(.chipAction(height: 32))
                if outcome.succeeded || outcome.safeStop {
                    Button("打开待支付订单") { onOpenOrders() }
                        .buttonStyle(.brandAction(height: 32))
                } else {
                    Button("调整配置重试") { onAdjust() }
                        .buttonStyle(.brandAction(height: 32))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, Theme.Space.md)
    }
}
