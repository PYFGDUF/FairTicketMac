import Foundation
import Testing
import FairTicketKit
@testable import FairTicketUI

@MainActor
@Suite("运行阶段文案")
struct RunStatusPresentationTests {
    @Test("每个运行阶段独立显示，等待时保留开售时间")
    func stageHeadlines() {
        let cases: [(RuntimeEvent.Phase?, String)] = [
            (nil, "正在准备任务"), (.preparing, "正在准备任务"),
            (.clock, "正在校准服务器时间"), (.stations, "正在加载站点"),
            (.login, "请扫码登录 12306"), (.waiting, "等待开售 · 17:00:00"),
            (.querying, "正在查询余票"), (.submitting, "正在提交订单，请勿退出应用"),
            (.queueing, "正在排队出票，请勿退出应用"), (.stopped, "任务已结束"),
            (.cancelled, "任务已停止"), (.failed, "任务失败，请查看日志")
        ]
        for (phase, expected) in cases {
            #expect(RunStatusPresentation.headline(phase: phase, stopping: false, start: "17:00:00") == expected)
            #expect(RunStatusPresentation.headline(phase: phase, stopping: true, start: "") == "正在停止任务…")
        }
    }

    @Test("新任务清空旧候选、结果和查询节奏")
    func resetPreviousRun() {
        let model = AppModel.preview(scenario: .queueing)
        model.resetRunState()
        #expect(model.latestCandidate == nil)
        #expect(model.queryCount == 0)
        #expect(model.currentQueryInterval == nil)
        #expect(model.runHeadline == "正在准备任务")
        #expect(!model.isStopping)
        #expect(!model.outcomeNeedsReview)
    }

    @Test("运行期间冻结购物车写入和排序")
    func runningFreezesCart() {
        let model = AppModel.preview(scenario: .queueing)
        let before = model.cartItems
        model.setCart([])
        if let first = before.first, let last = before.last { model.moveCartItem(first.id, to: last.id) }
        #expect(model.cartItems == before)
    }

}
