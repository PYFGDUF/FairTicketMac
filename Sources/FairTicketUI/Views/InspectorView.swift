import SwiftUI
import AppKit
import FairTicketKit

/// Live task status.
///
/// This column is the reason the layout has a third pane: the countdown and the query
/// cadence stay on screen while the form beside them is edited.  It is also the app's
/// visual anchor — a configuration window has no content of its own, so the release
/// countdown is treated as the main object, and it is the only surface in the window
/// that is lit rather than flat.
///
/// The design's arrangement, top to bottom: the heading with the run's state, the
/// countdown (or the pre-flight plan, or the outcome — one object, three states), the
/// two counters, the login, anything the engine refused to honour, and the run's own
/// timeline.
struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    /// Only for the empty state's "go and fill the trip in" button: the panel is allowed
    /// to be a way to the thing it is complaining about.
    @EnvironmentObject private var ui: UIState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.motionEnabled) private var motionEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                header
                primaryCard
                if let candidate = model.latestCandidate {
                    candidateCard(candidate)
                }
                metricsRow
                accountRow
                if model.isRunning, model.latestCandidate != nil {
                    InlineNote(
                        text: "已捕获余票，引擎正在提交订单。",
                        tone: .success
                    )
                }
                ForEach(model.preferenceWarnings, id: \.self) { message in
                    InlineNote(text: message, tone: .warning)
                }
                timelineCard
            }
            .padding(20)
            // The candidate card arrives while the user is watching this column, and the
            // cards under it should make room for it rather than jump.  Keyed on
            // presence, not on the card's text: the text changes with every query round
            // and re-springing the card each time would be the panel twitching, not the
            // one event worth interrupting the eye for.
            .motion(Theme.Motion.bouncy, value: model.latestCandidate != nil)
        }
        .background(Theme.rail(scheme))
    }

    // MARK: Header

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var header: some View {
        HStack(spacing: Theme.Space.xs) {
            Text("任务状态")
                .font(Theme.ui(17, .semibold))
                .foregroundStyle(Theme.textStrong(scheme))
            Spacer(minLength: 0)
            StatusPill(text: badgeText, tint: badgeTint)
        }
        .padding(.bottom, 2)
    }

    private var badgeText: String {
        switch model.runState {
        case .idle: return model.phase == .failed ? "失败" : "待配置"
        case .starting: return "正在启动"
        case .running: return model.phase?.title ?? "运行中"
        case .finished(let outcome):
            if outcome.safeStop { return "已安全停止" }
            if outcome.succeeded { return "出票成功" }
            if outcome.wasStoppedByUser { return "已停止" }
            return "已结束"
        }
    }

    private var badgeTint: Color {
        switch model.runState {
        case .idle: return model.phase == .failed ? Theme.danger(scheme) : Theme.textTertiary(scheme)
        case .starting, .running: return Theme.accentText(scheme)
        case .finished(let outcome):
            if outcome.safeStop { return Theme.accentText(scheme) }
            return outcome.succeeded ? Theme.success(scheme) : Theme.textTertiary(scheme)
        }
    }

    // MARK: Hero countdown

    /// How often the hero has to redraw, in three speeds.
    ///
    /// Ten hertz is only worth paying for during the last minute, where the tenths
    /// digit is real information rather than decoration — and where the user is
    /// actually watching.  While the wait is longer the readout prints whole seconds,
    /// so one hertz shows everything there is to show; after the release moment nothing
    /// changes at all.  The speed is derived from the model's own one-hertz tick, so it
    /// follows the state without the hero having to poll for it.
    enum Cadence: Equatable {
        /// Nothing is counting down, so there is no redraw worth scheduling.
        case idle
        /// Whole seconds are all the readout can show.
        case seconds
        /// The last minute: tenths, at ten hertz.
        case tenths

        static func forRemaining(_ remaining: Double?) -> Cadence {
            guard let remaining, remaining > 0 else { return .idle }
            return remaining <= 60 ? .tenths : .seconds
        }

        /// Seconds between redraws.
        ///
        /// `idle` is a minute rather than "never" because `TimelineView` has no stopped
        /// schedule — and a minute is honest: the readout is then a constant
        /// `--:--:--`, so nothing is missed by looking rarely.
        var redrawInterval: Double {
            switch self {
            case .idle: return 60
            case .seconds: return 1
            case .tenths: return 0.1
            }
        }
    }

    /// True once the release is inside the last minute.  Read from the model's own
    /// one-hertz tick, so the hero's tint flips once rather than at ten hertz.
    private var imminent: Bool {
        guard let remaining = model.remainingSeconds else { return false }
        return remaining <= 60
    }

    /// The one lit surface in the window: a brand wash behind white digits.
    ///
    /// A thin track under the digits shows how much of the warm-up window has elapsed —
    /// the only progress the engine can honestly report before the release moment — and
    /// it is derived from the engine's own two timestamps rather than from a spinner,
    /// which would claim progress it does not have.
    private var heroCard: some View {
        TimelineView(.periodic(from: .now, by: Cadence.forRemaining(model.remainingSeconds).redrawInterval)) { context in
            let remaining = model.countdown(at: context.date)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(remaining == nil ? "等待开售时刻" : "距离开售")
                        .font(Theme.ui(14, .medium))
                        .foregroundStyle(Theme.accentText(scheme))

                    // Deliberately not animated.  A rolling digit transition has to
                    // repaint the whole surface for the length of the curve, measured at
                    // ~23% of a core for the entire hour before a release — to animate
                    // one digit that the next tick replaces anyway.
                    Text(Self.readout(remaining))
                        .font(Theme.countdown)
                        .foregroundStyle(Theme.textStrong(scheme))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.top, 6)

                    Text(clockCaption)
                        .font(Theme.ui(14))
                        .foregroundStyle(Theme.textSecondary(scheme))
                        .padding(.top, 8)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    Theme.heroAtmosphere(for: scheme, imminent: imminent)
                }

                // The warm-up track sits on the card's own surface rather than in the
                // lit pool: it is a measure of elapsed time, not of the countdown.
                VStack(alignment: .leading, spacing: 8) {
                    warmUpTrack(at: context.date)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card(scheme))
            }
            .clipShape(heroShape)
        }
        .overlay(
            heroShape.strokeBorder(
                imminent ? Theme.brandEdge(scheme) : Color.clear,
                lineWidth: 1
            )
        )
        .motion(Theme.Motion.smooth, value: imminent)
    }

    /// Shared geometry for the hero surface: continuous curvature, matching the cards.
    private var heroShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
    }

    /// The engine's own release moment, plus whether the clock behind the countdown is
    /// calibrated — the two facts that decide whether the digits mean anything.
    private var clockCaption: String {
        guard let target = model.targetTimestamp else {
            return model.isRunning ? "已连接，等待引擎下发开售时刻" : "未开始任务"
        }
        let moment = Self.clock.string(from: Date(timeIntervalSince1970: target))
        return model.serverClockReady
            ? "开售时刻 \(moment) · 已完成校时"
            : "开售时刻 \(moment) · 未校时，按本地时间估算"
    }

    /// Elapsed fraction of the warm-up window as of `date`, or nil before the engine
    /// reports one.
    private func warmUpProgress(at date: Date) -> Double? {
        guard
            let start = model.queryStartTimestamp,
            let target = model.targetTimestamp,
            target > start
        else { return nil }
        let now = date.timeIntervalSince1970 + (model.clockOffsetSeconds ?? 0)
        return min(max((now - start) / (target - start), 0), 1)
    }

    @ViewBuilder
    private func warmUpTrack(at date: Date) -> some View {
        if let progress = warmUpProgress(at: date) {
            HStack(spacing: 6) {
                Text("热身进度")
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.textSecondary(scheme))
                Text("\(Int(progress * 100))%")
                    .font(Theme.data(13, .medium))
                    .foregroundStyle(Theme.text(scheme))
                Spacer(minLength: Theme.Space.xs)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track(scheme))
                    Capsule()
                        .fill(Theme.brand)
                        .frame(width: max(3, geometry.size.width * progress))
                        // Glided, not stepped.  The track is redrawn at this panel's own
                        // cadence — once a second, then ten times a second inside the last
                        // minute — so easing the fill over exactly one interval turns a
                        // stair-step into a continuous measure.  A spring is the wrong
                        // tool at every duration: a meter has to advance monotonically and
                        // take exactly as long as the tick it is catching up with, which
                        // is the one thing a linear curve guarantees.
                        .motion(
                            .linear(
                                duration: Cadence.forRemaining(model.remainingSeconds).redrawInterval
                            ),
                            value: progress
                        )
                }
            }
            .frame(height: 4)
        } else {
            Text(model.isRunning ? "等待进入热身窗口" : "设置开始时间后显示倒计时")
                .font(Theme.ui(14))
                .foregroundStyle(Theme.textTertiary(scheme))
        }
    }

    /// What the readout prints, at the precision its cadence can keep up to date.
    ///
    /// The format follows the cadence rather than a fixed rule: printing a tenths digit
    /// while the panel only redraws once a second would show a digit that is already
    /// stale, and printing whole seconds during the last minute would throw away the
    /// precision that minute is for.  Internal so the rule can be asserted.
    static func readout(_ remaining: Double?) -> String {
        guard let remaining else { return "--:--:--" }
        let total = Int(remaining)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        guard Cadence.forRemaining(remaining) == .tenths else {
            return hours > 0
                ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
                : String(format: "%02d:%02d", minutes, seconds)
        }
        let tenths = Int((remaining - Double(total)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    // MARK: Main object (three states)

    /// The panel's main object, which changes with how the run ended.
    ///
    /// The countdown is the panel's centre of gravity, so it keeps this slot even before
    /// a task starts: it then reads `--:--:--` under 等待开售时刻, which says "this is
    /// where the clock will be" instead of leaving the loudest surface in the window
    /// showing something else.  What the attempt would do is answered by the card below
    /// it rather than by replacing it.
    private var primaryCard: some View {
        ZStack(alignment: .top) {
            switch model.runState {
            case .idle, .starting, .running:
                heroCard.transition(.opacity)
            case .finished(let outcome):
                // The panel's third state.  Before it existed the run's *end* was the
                // only thing this column did not draw: after a successful grab the
                // loudest surface in the window sat on a dead `--:--:--`, captioned
                // 未开始任务, while the badge beside it said 出票成功.
                outcomeCard(outcome).transition(
                    .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                )
            }
        }
        // The same curve for both, and deliberately no bounce: this swap also happens on
        // every single start, and a run that begins with a bounce would be celebrating
        // something the user has not achieved yet.  The one beat belongs to the outcome.
        .motion(Theme.Motion.smooth, value: model.runState)
    }

    // MARK: Outcome (a finished run)

    /// What the panel becomes when a run ends.
    ///
    /// The full account of the run belongs in the result panel that the window opens at
    /// the same moment; this is the short form, so the column keeps saying something
    /// true after the countdown it was built around has gone.
    private func outcomeCard(_ outcome: RunOutcome) -> some View {
        let succeeded = outcome.succeeded
        let tint: Color = succeeded
            ? Theme.success(scheme)
            : (outcome.safeStop ? Theme.accentText(scheme) : Theme.textSecondary(scheme))

        return VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: RunOutcomePresentation.mark(outcome))
                    .font(Theme.ui(17, .semibold))
                    .foregroundStyle(tint)
                Text(RunOutcomePresentation.title(outcome))
                    .font(Theme.ui(17, .semibold))
                    .foregroundStyle(Theme.text(scheme))
                Spacer(minLength: 0)
            }
            Text(RunOutcomePresentation.detail(outcome))
                .font(Theme.ui(14))
                .foregroundStyle(Theme.textSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)

            if (succeeded || outcome.safeStop), let url = model.orderURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("打开 12306 订单", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.chipAction(height: 28))
                .help("到 12306 的待支付订单中核对并支付")
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: Candidate

    private func candidateCard(_ text: String) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "ticket.fill")
                .font(Theme.ui(15))
                .foregroundStyle(Theme.accentText(scheme))
            VStack(alignment: .leading, spacing: 2) {
                Text("命中候选")
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.textSecondary(scheme))
                Text(text)
                    .font(Theme.ui(15, .medium))
                    .foregroundStyle(Theme.text(scheme))
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        // Arriving candidates are the one event worth interrupting the eye for.  The
        // animation that plays this lives on the column above, because a transition only
        // plays inside an animation and this card cannot install one for its own
        // insertion — the modifier is not in the tree until the card is.
        .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
    }

    // MARK: Metrics

    /// The two counters the design puts side by side.
    ///
    /// Both are facts the engine reports or the cart states, and neither is derived:
    /// 备选 is the number of entries the run will work through, and it is deliberately
    /// *not* labelled 候选 — the engine uses "candidate" for a ticket source it has
    /// actually found, so calling cart entries candidates would make the panel disagree
    /// with the log about what has been hit.
    private var metricsRow: some View {
        HStack(spacing: Theme.Space.xs) {
            metricCard(
                name: model.isRunning ? "已发查询" : "查询次数",
                value: "\(model.queryCount)"
            )
            if model.isRunning {
                metricCard(
                    name: "自动提交",
                    value: model.bool("auto_submit") ? "已开启" : "已关闭",
                    tint: model.bool("auto_submit") ? Theme.success(scheme) : nil
                )
            } else {
                metricCard(name: "备选", value: "\(model.cartItems.count)")
            }
        }
    }

    private func metricCard(name: String, value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(Theme.fieldLabel)
                .foregroundStyle(Theme.textTertiary(scheme))
            Text(value)
                .font(Theme.metricFont)
                .foregroundStyle(tint ?? Theme.textStrong(scheme))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 11)
        .cardSurface(cornerRadius: 10)
    }

    // MARK: Login

    /// The account, in one row once it is known — and the code itself while it is not.
    ///
    /// The design collapses "logged in" to a single line, which is right: after the
    /// first scan the code is noise.  It cannot collapse the *unauthenticated* state,
    /// because a 160pt code is what the phone has to see.
    @ViewBuilder
    private var accountRow: some View {
        if model.showsLoginCode {
            loginCodeCard
        } else {
            HStack(spacing: Theme.Space.xs) {
                Circle()
                    .fill(qrTint)
                    .frame(width: 6, height: 6)
                Text(accountText)
                    .font(Theme.ui(15))
                    .foregroundStyle(Theme.text(scheme))
                Spacer(minLength: Theme.Space.xs)
                Text(accountDetail)
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.textTertiary(scheme))
                    .lineLimit(1)
                    // The button beside this is what the row exists for, so the caption
                    // is what yields when the column is at its narrowest.
                    .layoutPriority(-1)
                if model.qrStatus != nil {
                    Button("重新登录") { Task { await model.refreshLogin() } }
                        .buttonStyle(.chipAction(height: 26))
                        .fixedSize()
                        .disabled(!model.engineState.isReady)
                        .help(refreshHelp)
                }
            }
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(cornerRadius: 10)
        }
    }

    private var accountText: String {
        switch model.qrStatus {
        case .loggedIn, .confirmed: return "账号已登录"
        case .scanned: return "已扫码，等待手机确认"
        case .expired: return "登录已过期"
        case .waiting: return "等待扫码"
        default: return "未登录"
        }
    }

    private var accountDetail: String {
        switch model.qrStatus {
        case .loggedIn, .confirmed: return "登录状态有效"
        case .scanned: return "请在手机上确认"
        case .expired: return "需要重新扫码"
        default: return model.isRunning ? "正在生成二维码" : "开始任务时扫码"
        }
    }

    private var loginCodeCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Text("扫码登录")
                    .font(Theme.ui(15, .semibold))
                    .foregroundStyle(Theme.text(scheme))
                Spacer(minLength: Theme.Space.xs)
                StatusPill(text: model.qrStatus?.title ?? "未开始", tint: qrTint)
            }

            HStack(alignment: .top, spacing: Theme.Space.md) {
                qrView
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    // The code's own clock, one second, scoped to this label.
                    //
                    // Driving it from the model's ticker meant publishing every second
                    // while a code was on screen, and *any* publish on the model rebuilds
                    // every view in the window — a measured ~90 ms a pass, spent so that
                    // one label could count down.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(detailText(at: context.date))
                            .font(Theme.ui(14))
                            .foregroundStyle(Theme.textSecondary(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button("重新扫码") { Task { await model.refreshLogin() } }
                        .buttonStyle(.chipAction(height: 26))
                        .disabled(!model.engineState.isReady)
                        .help(refreshHelp)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// What the refresh control will actually do, given where the run is.
    ///
    /// The two states reach the engine through two different commands: a live run takes
    /// `refresh_qr`, which swaps the code without interrupting the task, and an idle one
    /// takes `reset_session`, which forgets the in-memory cookies.  `AppModel.refreshLogin`
    /// picks between them, so the run state here is the same fact it branches on rather
    /// than a guess at it.
    ///
    /// Deliberately *not* keyed off `maintenance_availability`: the sidecar drives the
    /// runner with a plain cancellation token, so that event reports `enabled: false` for
    /// every Mac session, and gating on it would grey out a command the engine honours.
    private var refreshHelp: String {
        model.isRunning
            ? "让正在运行的任务换一张新二维码，任务不会中断"
            : "清除内存中的登录状态，下次运行会重新生成二维码"
    }

    private var qrTint: Color {
        switch model.qrStatus {
        case .loggedIn, .confirmed: return Theme.success(scheme)
        case .expired: return Theme.accentText(scheme)
        case .scanned: return Theme.accentText(scheme)
        default: return Theme.textTertiary(scheme)
        }
    }

    /// 160pt is the size the desktop form uses because it is what the 12306 app
    /// scans reliably; shrinking it is not a cosmetic choice.
    private var qrView: some View {
        ZStack {
            if let data = model.qrImageData, let image = NSImage(data: data) {
                // Grouped so the white plate and the code arrive as one object — fading
                // the code in without its plate would flash a white square first.
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(.white)
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(6)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            } else {
                // An empty slot, not a blank white square: a QR code is always white,
                // so a white empty box would read as a code that failed to load.
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.well(scheme))
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(
                            Theme.hairline(scheme),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                    VStack(spacing: 6) {
                        Image(systemName: model.loginSlot.systemImage)
                            .font(Theme.ui(26, .light))
                            .foregroundStyle(Theme.textTertiary(scheme))
                        Text(model.loginSlot.text)
                            .font(Theme.ui(14))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.textSecondary(scheme))
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(width: Theme.qrDisplaySize, height: Theme.qrDisplaySize)
        // The code arriving is the moment the user has to act on, so it is the one place
        // in the inspector worth animating.  One-shot: it costs nothing while the code
        // sits there waiting to be scanned.
        .motion(Theme.Motion.bouncy, value: model.showsLoginCode)
    }

    private func detailText(at date: Date) -> String {
        if let expires = model.qrExpiresAt, model.qrStatus != .confirmed, model.qrStatus != .loggedIn {
            let remaining = max(0, expires - date.timeIntervalSince1970)
            return "有效期剩余 \(Int(remaining / 60)):\(String(format: "%02d", Int(remaining) % 60))"
        }
        if model.qrStatus == .loggedIn {
            return "会话仅驻留内存，本机不保存 Cookie，无需重新扫码。"
        }
        return "本机不保存 Cookie，每次启动需重新扫码。"
    }

    // MARK: Timeline

    /// The run's own timeline: the phases the engine has actually reported, most recent
    /// last.
    ///
    /// Read from `RuntimeEvent.Phase.timeline` rather than from the log, because the log
    /// is a page of its own and this column needs the last few steps, not every line.
    /// Only what the run has reached is shown: a list of every phase the engine *could*
    /// report reads as a checklist the user is failing to complete, which is exactly what
    /// the old version looked like before a task had even started.
    private var timelineCard: some View {
        let phases = recentPhases

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("运行时间线")
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textStrong(scheme))
                Spacer(minLength: Theme.Space.xs)
                if !phases.isEmpty {
                    Text("\(phases.count) 条")
                        .font(Theme.ui(13))
                        .foregroundStyle(Theme.textTertiary(scheme))
                }
            }
            .padding(.bottom, phases.isEmpty ? 6 : Theme.Space.sm)

            if phases.isEmpty {
                Text("任务开始后显示运行时间线")
                    .font(Theme.ui(14))
                    .foregroundStyle(Theme.textTertiary(scheme))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(phases.enumerated()), id: \.element) { offset, phase in
                        row(
                            phase: phase,
                            stepsBehind: phases.count - 1 - offset,
                            isLast: offset == phases.count - 1
                        )
                        // A phase list that advances is the one thing in this column that
                        // changes *shape* during a run.  The window holds three steps, so
                        // a new phase removes the oldest and appends one in the same
                        // transaction — the rows slide up and the new step rises into
                        // place, and the card's height does not move.
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .motion(Theme.Motion.snappy, value: phases)
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// The tail of the phase list, ending at wherever the run has got to.  Three entries
    /// is what fits the column without scrolling at this row rhythm — the point of the
    /// card is a glance, so a timeline that has to be scrolled to reach the live step is
    /// worse than one that names fewer steps.  The log page has the rest.
    private var recentPhases: [RuntimeEvent.Phase] {
        let all = RuntimeEvent.Phase.timeline
        let index = currentIndex
        guard index >= 0 else { return [] }
        let end = min(all.count, index + 1)
        return Array(all[max(0, end - 3)..<end])
    }

    private func row(phase: RuntimeEvent.Phase, stepsBehind: Int, isLast: Bool) -> some View {
        // Only a live run has a step in progress.  `phase` is whatever the engine last
        // reported and nothing clears it when the run ends, so without the `isRunning`
        // check the timeline went on printing 排队出票中 in brand orange directly under a
        // 已结束 badge — and under 出票成功, which is worse, because the two sentences
        // disagree about a fact the user acts on.
        let state: StepState = stepsBehind == 0 && model.isRunning ? .active : .done
        return HStack(alignment: .top, spacing: Theme.Space.md) {
            VStack(spacing: 6) {
                Circle()
                    .fill(dotTint(state))
                    .frame(width: 7, height: 7)
                // The connector takes whatever height the text column asks for, so the
                // rail stays attached to the next dot however far the rows are spaced.
                // A fixed 18pt stub left a bare gap under every row once the rhythm
                // opened up.
                if !isLast {
                    Rectangle()
                        .fill(Theme.track(scheme))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.top, 5)

            VStack(alignment: .leading, spacing: 5) {
                Text(phase.title)
                    .font(Theme.ui(14, state == .active ? .medium : .regular))
                    .foregroundStyle(
                        state == .active ? Theme.text(scheme) : Theme.textSecondary(scheme)
                    )
                Text(detail(for: phase, state: state))
                    .font(Theme.data(13))
                    .foregroundStyle(Theme.textTertiary(scheme))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        // The rows used to sit flush against each other, with nothing between two lines
        // of text but the stub of the rail — the steps read as one run-on block.
        .padding(.vertical, 8)
        .motion(Theme.Motion.snappy, value: state)
    }

    /// Done steps are green, the live one is the brand, and anything not yet reached is
    /// grey: three states, three readings, no words needed.
    private func dotTint(_ state: StepState) -> Color {
        switch state {
        case .done: return Theme.success(scheme)
        case .active: return Theme.accentText(scheme)
        case .pending: return Theme.textTertiary(scheme)
        }
    }

    /// One line under each phase: the fact that makes it worth reading.
    ///
    /// Everything comes from what the engine has actually reported, so a phase cannot
    /// claim a number the run has not produced.
    private func detail(for phase: RuntimeEvent.Phase, state: StepState) -> String {
        switch phase {
        case .clock:
            if let offset = model.clockOffsetSeconds, let rtt = model.clockRTTMilliseconds {
                return String(format: "偏差 %.0fms · RTT %.0fms", offset * 1000, rtt)
            }
            return state == .pending ? "等待校时" : "已校准"
        case .querying:
            return model.queryCount == 0 ? "等待首轮查询" : "已查询 \(model.queryCount) 次"
        case .submitting:
            switch state {
            case .pending: return "命中后自动提交"
            case .active: return "正在提交订单"
            case .done: return "已进入提交"
            }
        case .queueing:
            switch state {
            case .pending: return "提交后进入队列"
            case .active: return "排队出票中"
            case .done: return "已进入排队"
            }
        default:
            switch state {
            case .pending: return "等待中"
            case .active: return "进行中"
            case .done: return "已完成"
            }
        }
    }

    private enum StepState: Equatable { case pending, done, active }

    private var currentIndex: Int {
        guard let current = model.phase, let index = RuntimeEvent.Phase.timeline.firstIndex(of: current) else {
            return -1
        }
        return index
    }
}

// MARK: - Run outcome copy

/// What the panel says when a run ends.
///
/// Kept out of the view because it is the app's most consequential wording: after a
/// safe stop the server *may already hold the reservation*, so the sentence has to send
/// the user to the official order page rather than imply either success or failure.  A
/// rule that important is asserted in `OutcomePresentationTests` instead of being
/// reviewed by eye in a screenshot.
enum RunOutcomePresentation {
    static func title(_ outcome: RunOutcome) -> String {
        if outcome.succeeded { return "出票成功" }
        if outcome.safeStop { return "已安全停止" }
        return outcome.wasStoppedByUser ? "已停止" : "任务已结束"
    }

    static func detail(_ outcome: RunOutcome) -> String {
        if outcome.succeeded {
            return "服务端已受理这笔订单，请在 12306 的待支付订单中核对并支付。"
        }
        if outcome.safeStop {
            return "服务端可能已经受理了这笔订单，程序没有继续尝试其他车次。"
                + "请到 12306 的待支付订单中核对，避免重复下单。"
        }
        if outcome.wasStoppedByUser {
            return "任务已停止；修改参数后可以重新开始。"
        }
        return outcome.message.isEmpty ? "任务已结束。" : outcome.message
    }

    static func mark(_ outcome: RunOutcome) -> String {
        if outcome.succeeded { return "checkmark.seal.fill" }
        if outcome.safeStop { return "exclamationmark.shield.fill" }
        return outcome.wasStoppedByUser ? "stop.circle.fill" : "exclamationmark.circle.fill"
    }
}
