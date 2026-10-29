import FairTicketKit

/// Shared by the footer and the live page so a running task keeps its real stage.
enum RunStatusPresentation {
    static func headline(phase: RuntimeEvent.Phase?, stopping: Bool, start: String) -> String {
        if stopping { return "正在停止任务…" }
        switch phase {
        case .clock: return "正在校准服务器时间"
        case .stations: return "正在加载站点"
        case .login: return "请扫码登录 12306"
        case .waiting: return start.isEmpty ? "等待进入查询窗口" : "等待开售 · \(start)"
        case .querying: return "正在查询余票"
        case .submitting: return "正在提交订单，请勿退出应用"
        case .queueing: return "正在排队出票，请勿退出应用"
        case .stopped: return "任务已结束"
        case .cancelled: return "任务已停止"
        case .failed: return "任务失败，请查看日志"
        case .preparing, nil: return "正在准备任务"
        }
    }
}
