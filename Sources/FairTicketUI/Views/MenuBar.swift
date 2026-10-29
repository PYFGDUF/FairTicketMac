import SwiftUI
import AppKit

/// Menu bar item: the countdown while a task runs, the app icon otherwise.
///
/// Subscribes to the model itself rather than taking a snapshot, because a menu bar
/// label does not reliably redraw just because the containing scene was rebuilt.
public struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        if model.isRunning, let remaining = model.remainingSeconds {
            Text(Self.compact(remaining))
                .font(Theme.data(14, .medium))
        } else {
            Image(systemName: "tram.fill")
        }
    }

    private static func compact(_ remaining: Double) -> String {
        let total = max(0, Int(remaining))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// Menu bar drop-down.
///
/// The design's arrangement: what the run is doing at the top, then the actions that
/// only make sense to that state, then the window and app items.  Starting from here
/// goes through the same confirmation as the primary button, so the menu bar is a
/// shortcut and not a bypass.
public struct MenuBarMenu: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var ui: UIState
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        if model.isRunning {
            Text(countdownText)
            if !model.phaseMessage.isEmpty {
                Text(model.phaseMessage)
            }
            Text("已查询 \(model.queryCount) 次")
            Divider()
        } else {
            Text(model.engineState.isReady ? "引擎已就绪" : "引擎未连接")
            Divider()
        }

        // The design's order: the window first, then the one destructive act, then the
        // recoveries.  停止 sits second because it is the item someone opens this menu
        // in a hurry for.
        Button("打开主窗口") {
            openWindow(id: FairTicketWindow.mainID)
            NSApp.activate(ignoringOtherApps: true)
        }

        if model.isRunning {
            Button("停止当前任务") { Task { await model.stopTask() } }
        } else {
            Button("开始任务") { start() }
                .disabled(!model.engineState.isReady)
        }

        if let url = model.orderURL {
            Button("打开 12306 订单") { NSWorkspace.shared.open(url) }
        }

        Button("重新获取二维码") { Task { await model.refreshLogin() } }
            .disabled(!model.isRunning)

        Button("重新登录") { Task { await model.refreshLogin() } }
            .disabled(!model.engineState.isReady || model.isRunning)

        Button("查看运行日志") {
            ui.selectedSection = .log
            openWindow(id: FairTicketWindow.mainID)
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        // The same item the app menu shows: from here the About window is reachable
        // while the main window is closed, which is the state this menu exists for.
        AboutCommand()

        Button("退出 FairTicket") { NSApp.terminate(nil) }
    }

    /// The confirmation sheet lives in the main window, so the window has to be
    /// visible before the request is made.
    private func start() {
        openWindow(id: FairTicketWindow.mainID)
        NSApp.activate(ignoringOtherApps: true)
        Task {
            await model.requestStart()
            if let section = model.firstErrorSection { ui.selectedSection = section }
        }
    }

    private var countdownText: String {
        guard let remaining = model.remainingSeconds else { return "等待进入热身窗口" }
        let total = max(0, Int(remaining))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "距开售 %d:%02d:%02d", hours, minutes, seconds)
        }
        // Whole seconds only.  `remainingSeconds` is published once a second — the tenths
        // belong to the inspector panel's own clock — so a tenth printed from it here is a
        // leftover fraction that changes once a second while looking like a running
        // counter, which is a number the status item cannot actually deliver.
        return String(format: "距开售 %02d:%02d", minutes, seconds)
    }
}