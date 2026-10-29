import SwiftUI
import FairTicketKit

/// The main pane while a task is live.
///
/// The configuration form has nothing left to say during a run: every field is frozen
/// and the only question is "what is the engine seeing right now".  So the pane becomes
/// the run — the captured ticket source at the top, the query cadence under it — and the
/// form returns when the run ends.
struct LiveRunView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        PageHeader(
            title: model.latestCandidate == nil ? "运行中 · 高频查询余票" : "运行中 · 正在提交订单",
            subtitle: model.latestCandidate == nil
                ? "引擎正按查询间隔轮询余票，命中后自动切入下单。"
                : "已捕获余票，引擎正按购物车顺序尝试提交订单。",
            eyebrow: "LIVE · RUNNING"
        )
        .padding(.bottom, Theme.Space.xs)

        // Which alternative the engine is standing on right now, in its own sentence.
        if let attempt = model.attemptLine, !attempt.isEmpty {
            Text(attempt)
                .font(Theme.data(13))
                .foregroundStyle(Theme.textTertiary(scheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if model.latestCandidate != nil {
            hitCard
                // The run's one consequential moment, and the same treatment the
                // inspector gives an arriving candidate.  Insertion grows downward from
                // the card's own top edge into the space above the cadence list; removal
                // only fades, because the card leaves when the pane itself leaves.
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.97, anchor: .top).combined(with: .opacity),
                        removal: .opacity
                    )
                )
        }

        cadenceCard

        InlineNote(
            text: "提交成功后请前往 12306「待支付订单」核对。本工具不代付、不保存支付信息。",
            tone: .brand
        )
    }

    // MARK: Captured ticket

    /// The one lit surface in the main pane: the ticket the run is working on.
    private var hitCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: Theme.Space.xs) {
                    Text("余票已捕获")
                        .font(Theme.ui(13, .semibold))
                        .foregroundStyle(scheme == .dark ? Color(hex: 0x1A0E02) : Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.brand, in: Capsule())
                    if let seat = model.candidateSeat {
                        Text("\(seat) · \(StockToken.summary(model.candidateStock)) · 命中即停")
                            .font(Theme.data(13))
                            .foregroundStyle(Theme.textSecondary(scheme))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                Text(headline)
                    .font(Theme.ui(22, .semibold))
                    .foregroundStyle(Theme.textStrong(scheme))
                    .lineLimit(1)

                Text(subline)
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.textSecondary(scheme))
                    .lineLimit(1)
            }
            .padding(20)

            Rectangle()
                .fill(Theme.hairline(scheme))
                .frame(height: 1)

            HStack(alignment: .top, spacing: 0) {
                stat(
                    name: "\(model.candidateSeat ?? "席别")可抢",
                    value: StockToken.short(model.candidateStock),
                    mono: true,
                    tint: Theme.brand
                )
                stat(
                    name: "请求间隔",
                    value: intervalText(model.currentQueryInterval),
                    mono: true
                )
                stat(name: "查询轮次", value: roundText, mono: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(Theme.hitAtmosphere(for: scheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
    }

    /// "12 / 1000" when the engine has reported its round ceiling, the bare count when
    /// it has not: the ceiling arrives on the same `query` frame as the attempt, so the
    /// only honest alternatives are the pair or the count alone.
    private var roundText: String {
        guard let limit = model.queryRoundLimit else { return "\(model.queryCount)" }
        return "\(model.queryCount) / \(limit)"
    }

    private var headline: String {
        let train = model.candidateTrain ?? ""
        guard let pair = routePair else { return train }
        return "\(train) \(pair.0) → \(pair.1)"
    }

    private var subline: String {
        var parts: [String] = []
        let date = model.string("train_date")
        if !date.isEmpty { parts.append(String(date.suffix(5))) }
        if let departure = model.candidateDepartureTime, !departure.isEmpty {
            parts.append("\(departure) 发车")
        }
        if let seat = model.candidateSeat {
            // "N 张可提交" only where the server actually counted; otherwise it said 有
            // or nothing at all, and a unit would be an invented number.
            parts.append(
                StockToken.isCountable(model.candidateStock)
                    ? "\(seat) \(StockToken.short(model.candidateStock))可提交"
                    : "\(seat) \(StockToken.summary(model.candidateStock))"
            )
        }
        return parts.joined(separator: " · ")
    }

    /// The station pair the captured train belongs to, when the cart names exactly one.
    private var routePair: (String, String)? {
        var pairs: [(String, String)] = []
        for item in model.cartItems {
            let pair = (item.fromStation, item.toStation)
            if !pairs.contains(where: { $0.0 == pair.0 && $0.1 == pair.1 }) { pairs.append(pair) }
        }
        return pairs.count == 1 ? pairs[0] : nil
    }

    private func stat(name: String, value: String, mono: Bool = false, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(Theme.fieldLabel)
                .foregroundStyle(Theme.textTertiary(scheme))
            Text(value)
                .font(mono ? Theme.data(16, .medium) : Theme.ui(16, .semibold))
                .foregroundStyle(tint ?? Theme.textStrong(scheme))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Cadence

    /// How the run paces itself.
    ///
    /// The engine steps its interval exactly twice (`runner.py::_current_query_interval`):
    /// the hot rate applies from `pre_query_seconds` before the release moment until
    /// `hot_window_seconds` after it, and the regular rate applies everywhere else.  Both
    /// bounds are user-settable on 高级参数, so the card reads them back rather than
    /// repeating a fixed number the engine would happily contradict.
    private var cadenceCard: some View {
        Card(title: "实时查询节奏") {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("开售前 \(secondsText(model.double("pre_query_seconds")))进入高频轮询，持续到开售后 \(secondsText(model.double("hot_window_seconds")))")
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.textTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 0) {
                    cadenceRow(
                        state: .done,
                        title: "常规查询 · 间隔 \(intervalText(model.double("query_interval_seconds")))",
                        detail: windowText + " · 已完成"
                    )
                    cadenceRow(
                        state: model.latestCandidate == nil ? .active : .done,
                        title: "热身高频 · 间隔 \(intervalText(model.double("hot_query_interval_seconds")))",
                        detail: "开售前后至命中 · " + (model.latestCandidate == nil ? "进行中" : "已完成")
                    )
                    cadenceRow(
                        state: model.latestCandidate == nil ? .pending : .active,
                        title: "余票捕获并提交订单",
                        detail: "命中后触发 · 命中即停"
                    )
                }
            }
        }
    }

    private var windowText: String {
        let start = model.string("start_at")
        let stop = model.string("stop_at")
        if start.isEmpty { return "启动即开始" }
        return stop.isEmpty ? "\(start) 起" : "\(start) → \(stop)"
    }

    private func intervalText(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        return String(format: "%.2f s", seconds)
    }

    /// Whole seconds when the setting is a whole number, otherwise the two decimals the
    /// control itself offers — rounding 1.50 s up to "2 秒" would state a pacing rule the
    /// engine does not follow.
    private func secondsText(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        return seconds == seconds.rounded()
            ? String(format: "%.0f 秒", seconds)
            : String(format: "%.2f 秒", seconds)
    }

    private enum CadenceState { case done, active, pending }

    private func cadenceRow(state: CadenceState, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Circle()
                .fill(
                    state == .done
                        ? Theme.success(scheme)
                        : (state == .active ? Theme.brand : Theme.textTertiary(scheme))
                )
                .frame(width: 7, height: 7)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.ui(14, state == .pending ? .regular : .medium))
                    .foregroundStyle(
                        state == .pending ? Theme.textSecondary(scheme) : Theme.text(scheme)
                    )
                Text(detail)
                    .font(Theme.data(13))
                    .foregroundStyle(Theme.textTertiary(scheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        // The three steps hand over to each other as the run advances; easing the dot and
        // the weight keeps that reading as one list moving on rather than three rows
        // being redrawn.
        .motion(Theme.Motion.snappy, value: state)
    }
}
