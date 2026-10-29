import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FairTicketKit

// The menu bar the window's controls are mirrored into.
//
// HIG 1.1: the menu bar is a Mac app's primary discovery surface — "users who cannot find
// a feature will look in the menu bar before anywhere else".  Before this file the app's
// most important action existed only as a button at the bottom of the form and in the
// menu-bar extra, so someone looking for 开始任务 in the menus found nothing at all, and
// four actions had no keyboard equivalent (HIG 1.2, 5.1).
//
// The commands read the model through a focused value rather than observing it.
// `AppModel` publishes a countdown up to ten times a second during the run-up, and a menu
// that observed it would rebuild the whole menu bar at that rate; enable/disable state
// comes from a small `Equatable` snapshot instead, so a menu re-renders only when one of
// the flags it shows actually flips.

// MARK: - Focused values

private struct AppModelFocusedKey: FocusedValueKey {
    typealias Value = AppModel
}

private struct TaskAvailabilityFocusedKey: FocusedValueKey {
    typealias Value = TaskCommandAvailability
}

extension FocusedValues {
    /// The running model, so a menu item can act on it.
    ///
    /// A reference, not a closure: a closure stored in a focused-value key is both
    /// non-comparable and a re-render hazard.
    var appModel: AppModel? {
        get { self[AppModelFocusedKey.self] }
        set { self[AppModelFocusedKey.self] = newValue }
    }

    /// Just the flags the Task menu draws its enabled state from.
    var taskAvailability: TaskCommandAvailability? {
        get { self[TaskAvailabilityFocusedKey.self] }
        set { self[TaskAvailabilityFocusedKey.self] = newValue }
    }
}

/// What the Task menu needs to know — deliberately not the whole model.
///
/// HIG 1.3 asks menu items to reflect current state; taking a five-Bool snapshot is what
/// lets them do that without the menu observing a countdown that ticks ten times a second.
public struct TaskCommandAvailability: Equatable, Sendable {
    public var isRunning: Bool
    public var canStart: Bool
    public var hasOrder: Bool

    public init(isRunning: Bool, canStart: Bool, hasOrder: Bool) {
        self.isRunning = isRunning
        self.canStart = canStart
        self.hasOrder = hasOrder
    }

    /// HIG 1.3's "disable items that are not applicable", as one rule rather than three
    /// `disabled(...)` expressions spread over the menu.
    ///
    /// A start is offered exactly when the engine is connected, no run is in flight, and
    /// the last run's result has been read — the same gate the window's own button uses,
    /// so the menu and the button can never disagree about whether starting is possible.
    /// The third clause is what keeps ⌘↩ from queueing a briefing *behind* the result
    /// panel, where it could not be seen and would then open unasked.
    @MainActor
    public init(model: AppModel) {
        self.init(
            isRunning: model.isRunning,
            canStart: model.engineState.isReady && !model.isRunning && !model.outcomeNeedsReview,
            hasOrder: model.orderURL != nil
        )
    }
}

// MARK: - File

/// 文件 menu: the settings exchange and the official order page.
///
/// HIG 1.1 omits the File menu only for apps that are not document-based.  This one is
/// not, but it *does* exchange a file (the version-5 settings JSON), and that exchange
/// lived only in two toolbar buttons with no shortcut — the two commands a Mac user
/// reaches for first, ⌘O and ⇧⌘S, did nothing.
public struct FileCommands: View {
    @FocusedValue(\.appModel) private var model

    public init() {}

    public var body: some View {
        Button("导入设置…") {
            Task { await SettingsFiles.importSettings(into: model) }
        }
        .keyboardShortcut("o", modifiers: .command)
        // The same gate the toolbar's 导入 uses.  An import replaces the whole draft,
        // which the engine is reading round by round — so the menu item must not be a
        // way to do mid-run what the button next to it refuses to do.
        .disabled(model == nil || model?.isRunning == true)

        Button("保存设置为…") {
            Task { await SettingsFiles.saveSettings(from: model) }
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .disabled(model == nil || model?.isRunning == true)

        Divider()

        Button("打开 12306 订单") {
            if let url = model?.orderURL { NSWorkspace.shared.open(url) }
        }
        .disabled(model?.orderURL == nil)
    }
}

/// The open/save panels, in one place.
///
/// The toolbar buttons and the File menu item both end here: two call sites building
/// their own `NSOpenPanel` is how the allowed file type or the panel's wording drifts
/// apart between the button and the menu.
enum SettingsFiles {
    @MainActor
    static func importSettings(into model: AppModel?) async {
        guard let model else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "导入界面参数"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await model.importSettings(from: url)
    }

    @MainActor
    static func saveSettings(from model: AppModel?) async {
        guard let model else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "fairticket.json"
        panel.message = "保存界面参数"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await model.saveSettings(to: url)
    }
}

// MARK: - Task

/// 任务 menu: the app's own commands, in the order they are used.
///
/// The primary action belongs here rather than only at the bottom of the form: the menu
/// bar is where a Mac user looks for "run this", and it is the only place a shortcut works
/// no matter which control in the window has focus.
public struct TaskCommands: View {
    @FocusedValue(\.appModel) private var model
    @FocusedValue(\.uiState) private var ui
    @FocusedValue(\.taskAvailability) private var availability

    public init() {}

    public var body: some View {
        Button("开始任务…") {
            Task { await start() }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!(availability?.canStart ?? false))

        Button("停止任务") {
            Task { await model?.stopTask() }
        }
        .keyboardShortcut(".", modifiers: .command)
        .disabled(!(availability?.isRunning ?? false))

        Divider()

        Button("检查配置") {
            Task { await model?.validate(byRequest: true) }
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(!(availability?.canStart ?? false))

        // HIG 1.3: the title states what the item will do, not what the state is.
        Button(ui?.showInspector == true ? "隐藏任务状态" : "显示任务状态") {
            ui?.toggleInspector()
        }
        .keyboardShortcut("i", modifiers: [.command, .option])
        .disabled(ui == nil)
    }

    /// The same path the window's own button takes: ask, then go to whatever the engine
    /// refused, so the menu is a second entrance to one behaviour rather than a second
    /// implementation of it.
    private func start() async {
        guard let model else { return }
        await model.requestStart()
        if let section = model.firstErrorSection { ui?.selectedSection = section }
    }
}

// MARK: - Help

/// 帮助 menu.  It was replaced with an empty group, so the app shipped with no Help menu
/// at all — HIG 1.1 lists Help among the menus every app must have, and it is the one
/// place a user looks when the interface has not explained itself.
public struct HelpCommands: View {
    public init() {}

    public var body: some View {
        Button("使用说明") { open(FairTicketProject.documentationURL) }
        Button("抢票原理") { open(FairTicketProject.principleURL) }
        Divider()
        Button("项目主页") { open(FairTicketProject.repositoryURL) }
        Button("反馈问题…") { open(FairTicketProject.issuesURL) }
        Divider()
        Button("打开 12306 官网") { open(FairTicketProject.railwayURL) }
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
