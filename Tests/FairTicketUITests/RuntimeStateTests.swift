import Foundation
import Testing
import FairTicketKit
@testable import FairTicketUI

/// Terminal states and the phase timeline.
///
/// The safe-stop path is the one that can cost money if the interface gets it
/// wrong, so "stop and check the official order page" is asserted rather than
/// eyeballed.
@MainActor
@Suite("运行状态")
struct RuntimeStateTests {

    @Test("安全停止会阻断界面并提供订单入口")
    func safeStopBlocksAndPointsAtTheOrderPage() throws {
        let model = AppModel.preview(scenario: .safeStop)

        let message = try #require(model.safeStopMessage, "安全停止必须提示，而不是只写日志")
        #expect(message.contains("12306"))
        #expect(!model.isRunning)
        #expect(model.orderURL != nil, "没有订单入口的话提示无路可走")

        if case .finished(let outcome) = model.runState {
            #expect(outcome.safeStop)
            #expect(!outcome.succeeded)
        } else {
            Issue.record("安全停止后必须离开运行态")
        }
    }

    @Test("关闭提示后不再阻断")
    func dismissingTheSafeStopNoticeClearsIt() {
        let model = AppModel.preview(scenario: .safeStop)
        #expect(model.safeStopMessage != nil)

        model.clearSafeStop()

        #expect(model.safeStopMessage == nil)
    }

    @Test("命中候选被拼成一行可读文本")
    func candidateIsRenderedAsOneLine() throws {
        let model = AppModel.preview(scenario: .queueing)

        let candidate = try #require(model.latestCandidate)
        #expect(candidate.contains("G79"))
        #expect(candidate.contains("二等座"))
        #expect(candidate.contains("有"))
    }

    @Test("偏好降级会进警告列表")
    func preferenceDowngradesAreCollected() {
        let model = AppModel.preview(scenario: .queueing)

        #expect(model.preferenceWarnings.count == 1)
        #expect(model.preferenceWarnings.first?.contains("座位关系") == true)
    }

    @Test("阶段推进按时间线顺序走")
    func phasesFollowTheTimeline() throws {
        let model = AppModel.preview(scenario: .queueing)

        let phase = try #require(model.phase)
        #expect(RuntimeEvent.Phase.timeline.contains(phase))

        let index = try #require(RuntimeEvent.Phase.timeline.firstIndex(of: phase))
        #expect(index > RuntimeEvent.Phase.timeline.firstIndex(of: .login) ?? 0)
        #expect(model.phaseMessage.contains("排队"))
    }

    @Test("运行中的排队等待时间进入阶段说明")
    func queueWaitTimeIsShown() {
        let model = AppModel.preview(scenario: .queueing)
        model.apply(RuntimeEvent(rawKind: "order_wait", data: ["wait_time": .number(9)]))

        #expect(model.phaseMessage.contains("9"))
    }

    @Test("运行中的任务会被判定为 isRunning")
    func runningStateIsReported() {
        let model = AppModel.preview(scenario: .running)

        #expect(model.isRunning)
        #expect(model.engineState.isReady)
    }

    @Test("重新扫码会清掉二维码与状态")
    func resetSessionClearsTheLogin() {
        let model = AppModel.preview(scenario: .login)
        #expect(model.showsLoginCode)

        model.clearLoginState()

        #expect(!model.showsLoginCode)
        #expect(model.qrStatus == nil)
        #expect(model.qrExpiresAt == nil)
    }
}