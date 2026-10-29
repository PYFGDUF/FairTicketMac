import AppKit
import SwiftUI
import FairTicketKit

// The window's fixed furniture: the bar across the top, the bar across the bottom.
//
// Both of them span the full width, which is the design document's arrangement and
// the reason the window is no longer a `NavigationSplitView`: a split view can only
// put toolbars *inside* the detail column, so the brand and the primary action ended
// up in the title bar with AppKit's own chrome around them.  Here the two bars are
// ordinary views in a `VStack`, so they can be laid out like the rest of the app.

// MARK: - Brand

/// The app mark: the design icon reduced to a tile.
///
/// The icon page specifies a 135° gradient from `#FF7A17` to `#F44A0D` on a rounded
/// square whose radius is 22.5% of its side.  At top-bar size the train glyph is
/// unreadable, so the tile carries the colour and a white "F" — the mark the design's
/// own header uses.
struct AppMark: View {
    var size: CGFloat = 26

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Theme.brandMark(for: scheme))
            .overlay(
                Text("F")
                    .font(Theme.ui(size * 0.52, .bold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
    }
}

// MARK: - Top bar

/// The window's header.
///
/// Three zones, as in the design: the mark and the app's name, the engine's own state
/// in the middle, and the three file-level actions on the right.  The engine state
/// lives here rather than in the sidebar footer because it is the one piece of status
/// that is true of the whole window — and because a bar that says only "FairTicket"
/// wastes the widest strip in the UI.
struct TopBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var ui: UIState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.xs) {
                AppMark(size: 28)
                Text("FairTicket")
                    .font(Theme.ui(17, .semibold))
                    .foregroundStyle(Theme.textStrong(scheme))
            }

            Spacer(minLength: Theme.Space.md)

            EngineBadge()

            Spacer(minLength: Theme.Space.md)

            HStack(spacing: 2) {
                plainAction("导入") {
                    Task { await SettingsFiles.importSettings(into: model) }
                }
                .disabled(!model.engineState.isReady || model.isRunning)
                .help("导入 version 5 JSON（⌘O）")

                plainAction("保存为") {
                    Task { await SettingsFiles.saveSettings(from: model) }
                }
                .disabled(!model.engineState.isReady || model.isRunning)
                .help("保存全部可编辑参数为 version 5 JSON（⇧⌘S）")

                Button {
                    Task { await model.validate(byRequest: true) }
                } label: {
                    Text("检查配置")
                }
                .buttonStyle(.inverseAction)
                .disabled(!model.engineState.isReady || model.isRunning)
                .help("立即检查全部参数并标出问题字段（⇧⌘R）")
                .padding(.leading, 6)
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .frame(height: Theme.Layout.topBarHeight)
        .background(Theme.canvas(scheme))
    }

    /// The design's quiet top-bar action: a word, no icon.
    ///
    /// The three window actions used to carry glyphs, which put four different marks on
    /// one line and made the one button that matters — 检查配置 — read as the fourth of
    /// four equal controls instead of as the one filled action.
    private func plainAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.ui(15))
                .foregroundStyle(Theme.textSecondary(scheme))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.topBarAction)
    }
}

/// Hover feedback for a top-bar word: a quiet chip, no resting background.
struct TopBarActionStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.motionEnabled) private var motionEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                hovering && isEnabled ? Theme.chip(scheme) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && isEnabled ? Theme.Control.pressScale : 1)
            .onHover { hovering = $0 }
            .animation(motionEnabled ? Theme.Motion.press : nil, value: hovering)
            .animation(motionEnabled ? Theme.Motion.press : nil, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TopBarActionStyle {
    static var topBarAction: TopBarActionStyle { TopBarActionStyle() }
}

/// The engine's state, as the design's centred capsule.
///
/// A dot plus two words.  It is deliberately not a button: nothing here needs to be
/// pressed to fix a connection — the alert on failure already offers a retry — and a
/// capsule that looks pressable but is not is worse than one that reads as a label.
struct EngineBadge: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.motionEnabled) private var motionEnabled

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(text)
                .font(Theme.ui(14, .medium))
                .foregroundStyle(Theme.text(scheme))
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 11)
        .frame(height: 26)
        .background(Theme.chipHover(scheme), in: Capsule())
        .help(model.engineDescription)
        // The engine coming up is the window's first event, and the dot's colour is the
        // whole message: a crossfade lets orange become green in place, rather than the
        // capsule redrawing into a different sentence.
        .animation(motionEnabled ? Theme.Motion.snappy : nil, value: model.engineState)
    }

    private var tint: Color {
        switch model.engineState {
        case .ready: return Theme.success(scheme)
        case .connecting: return Theme.accentText(scheme)
        case .idle: return Theme.textTertiary(scheme)
        case .failed: return Theme.danger(scheme)
        }
    }

    private var text: String {
        switch model.engineState {
        case .idle: return "引擎未连接"
        case .connecting: return "正在启动引擎…"
        case .ready: return "引擎已就绪"
        case .failed: return "引擎连接失败"
        }
    }
}

// MARK: - Bottom bar

/// The window's footer: what the draft will do, and the one control that starts it.
///
/// The primary action lives here rather than in the top bar because the design puts
/// it at the end of the reading path — after the form, not before it — and because a
/// disabled button needs somewhere to say what it is waiting for.
struct BottomBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var ui: UIState
    @Environment(\.colorScheme) private var scheme

    /// What the bar says about the button beside it.
    ///
    /// `ready` shows nothing on purpose in the *pill* sense: "ready" would be a claim the
    /// app cannot make before the engine has actually checked the draft, and the button
    /// that performs that check sits right there.  The rule lives here, apart from the
    /// copy, so the order can be asserted without a window.
    enum Readiness: Equatable {
        case engineNotReady
        case needsAttention(Int)
        case running
        case ready

        /// Blocking states first: an engine that never came up is the only one of these
        /// the user cannot work around, and while a task is running the form's problems
        /// are not what the button will act on.
        static func of(engineReady: Bool, visibleErrors: Int, isRunning: Bool) -> Readiness {
            if !engineReady { return .engineNotReady }
            if isRunning { return .running }
            if visibleErrors > 0 { return .needsAttention(visibleErrors) }
            return .ready
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            status

            Spacer(minLength: Theme.Space.md)

            HStack(spacing: 8) {
                if model.isRunning {
                    Button("打开日志") { ui.selectedSection = .log }
                        .buttonStyle(.chipAction)

                    Button("重新获取二维码") { Task { await model.refreshLogin() } }
                        .buttonStyle(.chipAction)
                } else {
                    // The design's mode switch, named for what pressing it *does*: the
                    // bar's own summary already says which mode is live, so a button
                    // repeating it would leave nothing to press.
                    Button(model.bool("auto_submit") ? "仅监控" : "自动提交") {
                        model.setBool("auto_submit", !model.bool("auto_submit"))
                    }
                    .buttonStyle(.chipAction)
                    .help(
                        model.bool("auto_submit")
                            ? "改为仅监控：只查询余票，命中后不向 12306 提交订单"
                            : "改为自动提交：命中余票后直接向 12306 提交订单"
                    )
                }

                Button("12306 订单") { openOrderPage() }
                    .buttonStyle(.chipAction)
                    .disabled(model.orderURL == nil)

                if model.isRunning {
                    Button("停止任务") { Task { await model.stopTask() } }
                        .buttonStyle(.inverseAction)
                        .help("停止查询（⌘.）；已在途的订单请求不会因此取消，请到 12306 核对")
                } else {
                    Button("开始任务") {
                        Task {
                            await model.requestStart()
                            if let section = model.firstErrorSection {
                                ui.selectedSection = section
                            }
                        }
                    }
                    .buttonStyle(.brandAction(height: 36))
                    .disabled(!model.engineState.isReady)
                    .help("先检查配置，然后确认本次尝试的范围与顺序（⌘↩）")
                }
            }
        }
        .padding(.horizontal, Theme.Layout.pageInset)
        .frame(height: Theme.Layout.bottomBarHeight)
        .background(Theme.rail(scheme))
    }

    /// What will happen, plus the three facts that describe the attempt.
    ///
    /// The old bar carried a readiness *pill* on the right; the design puts the whole
    /// sentence on the left, where it reads as a statement about the form rather than
    /// as a badge on the button.
    private var status: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(headline)
                .font(Theme.ui(15, .semibold))
                .foregroundStyle(headlineTint)
                // The bar's sentence and its colour both turn over when a run starts or
                // ends, and `ContentView` already animates that state; without this the
                // words swap mid-frame while the layout around them eases.
                .contentTransition(.opacity)
            Text(summary)
                .font(Theme.ui(13))
                .foregroundStyle(Theme.textSecondary(scheme))
                .lineLimit(1)
        }
    }

    /// What the draft is about to attempt, said as a sentence.
    private var readiness: Readiness {
        Readiness.of(
            engineReady: model.engineState.isReady,
            visibleErrors: model.visibleErrorTotal,
            isRunning: model.isRunning
        )
    }

    private var headline: String {
        switch readiness {
        case .engineNotReady: return "等待引擎就绪"
        case .running: return model.runHeadline
        case .needsAttention(let count): return "\(count) 项参数需要修改"
        // An empty cart is not a form error — the engine accepts it and would simply
        // monitor — so it is not part of the readiness rule, only of the wording.
        case .ready:
            if case .finished(let outcome) = model.runState, outcome.succeeded {
                return "订单已提交，请核对并支付"
            }
            return model.cartItems.isEmpty ? "尚未加入备选" : "配置就绪，可开始任务"
        }
    }

    private var headlineTint: Color {
        switch readiness {
        case .engineNotReady: return Theme.textSecondary(scheme)
        case .running: return Theme.textStrong(scheme)
        case .needsAttention: return Theme.danger(scheme)
        case .ready: return Theme.text(scheme)
        }
    }

    /// The three facts the desktop form reports before a run: how many alternatives,
    /// how many people, and when it will start.
    private var summary: String {
        var parts: [String] = []
        parts.append("\(model.cartItems.count) 个备选")
        let people = model.listItems("passenger_names")
        parts.append("\(people.count) 位乘车人")

        let date = model.string("train_date")
        let start = model.string("start_at")
        if !date.isEmpty {
            parts.append(start.isEmpty ? "\(date) \(modeLabel)" : "\(date) \(start) \(modeLabel)")
        } else {
            parts.append(modeLabel)
        }
        return parts.joined(separator: " · ")
    }

    private var modeLabel: String {
        model.bool("auto_submit") ? "自动提交" : "仅监控"
    }

    private func openOrderPage() {
        if let url = model.orderURL { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Buttons
//
// The primary action's style lives in `Controls.swift` beside the field chrome it
// shares a radius with; the rest are here because only the chrome uses them.

/// The design's secondary action: a quiet capsule one step above the bar it sits on.
struct ChipActionStyle: ButtonStyle {
    var height: CGFloat = 32

    @Environment(\.colorScheme) private var scheme
    @Environment(\.motionEnabled) private var motionEnabled
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(15, .medium))
            .foregroundStyle(isEnabled ? Theme.text(scheme) : Theme.textTertiary(scheme))
            .padding(.horizontal, Theme.Space.md)
            .frame(height: height)
            .background(
                Theme.card(scheme),
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed && motionEnabled ? Theme.Control.pressScale : 1)
            .animation(motionEnabled ? Theme.Motion.press : nil, value: configuration.isPressed)
    }
}

/// The design's inverted action — a white capsule on dark, black on light.
///
/// Used for 检查配置 and 停止任务: the two moments where the window asks for a decision
/// rather than a configuration edit.  It is the strongest neutral surface available,
/// so it never competes with the brand for the eye.
struct InverseActionStyle: ButtonStyle {
    var height: CGFloat = 30

    @Environment(\.colorScheme) private var scheme
    @Environment(\.motionEnabled) private var motionEnabled
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.ui(15, .semibold))
            .foregroundStyle(
                isEnabled
                    ? (scheme == .dark ? Color(hex: 0x0A0A0A) : Color(hex: 0xFFFFFF))
                    : Theme.textTertiary(scheme)
            )
            .padding(.horizontal, Theme.Space.md)
            .frame(height: height)
            .background(
                isEnabled
                    ? AnyShapeStyle(scheme == .dark ? Color(hex: 0xE8E8E8) : Color(hex: 0x1A1A1A))
                    : AnyShapeStyle(Theme.chip(scheme)),
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed && motionEnabled ? Theme.Control.pressScale : 1)
            .animation(motionEnabled ? Theme.Motion.press : nil, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ChipActionStyle {
    static var chipAction: ChipActionStyle { ChipActionStyle() }
    static func chipAction(height: CGFloat) -> ChipActionStyle {
        ChipActionStyle(height: height)
    }
}

extension ButtonStyle where Self == InverseActionStyle {
    static var inverseAction: InverseActionStyle { InverseActionStyle() }
    static func inverseAction(height: CGFloat) -> InverseActionStyle {
        InverseActionStyle(height: height)
    }
}
