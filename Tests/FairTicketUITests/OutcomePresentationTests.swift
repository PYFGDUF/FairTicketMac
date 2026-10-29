import Foundation
import Testing
import FairTicketKit
@testable import FairTicketUI

/// The wording the panel shows when a run ends.
///
/// This is the app's most consequential copy: after a safe stop the server *may already
/// hold the reservation*, so the sentence has to send the user to the official order page
/// without implying either success or failure.  A rule that load-bearing is asserted here
/// rather than checked by eye in a screenshot of one state.
@Suite("结束状态文案")
struct OutcomePresentationTests {

    private func outcome(exitCode: Int, safeStop: Bool = false, cancelled: Bool = false, message: String = "") -> RunOutcome {
        RunOutcome(event: RuntimeEvent(
            rawKind: "exit",
            message: message,
            data: [
                "exit_code": .number(Double(exitCode)),
                "safe_stop": .bool(safeStop),
                "cancelled": .bool(cancelled),
            ]
        ))
    }

    @Test("退出码 0 才算成功")
    func onlyExitZeroSucceeds() {
        #expect(outcome(exitCode: 0).succeeded)
        #expect(!outcome(exitCode: 1).succeeded)
        #expect(!outcome(exitCode: 130).succeeded)
    }

    @Test("安全停止不会被说成成功，也不会被说成失败")
    func safeStopNeverReadsAsSuccessOrFailure() {
        let safeStop = outcome(exitCode: 1, safeStop: true)
        let detail = RunOutcomePresentation.detail(safeStop)

        #expect(RunOutcomePresentation.title(safeStop) == "已安全停止")
        // The two halves that matter: it may have gone through, and it must be checked
        // by hand before trying again.
        #expect(detail.contains("可能已经受理"))
        #expect(detail.contains("避免重复下单"))
        #expect(!detail.contains("失败"))
    }

    @Test("成功时指向待支付订单，而不是宣布结束")
    func successPointsAtTheOrderPage() {
        let succeeded = outcome(exitCode: 0)
        #expect(RunOutcomePresentation.title(succeeded) == "出票成功")
        #expect(RunOutcomePresentation.detail(succeeded).contains("待支付订单"))
        #expect(RunOutcomePresentation.mark(succeeded) == "checkmark.seal.fill")
    }

    @Test("用户主动停止与失败分开描述")
    func userStopIsNotAFailure() {
        let stopped = outcome(exitCode: 130, cancelled: true)
        #expect(stopped.wasStoppedByUser)
        #expect(RunOutcomePresentation.title(stopped) == "已停止")
        #expect(RunOutcomePresentation.detail(stopped).contains("重新开始"))
    }

    @Test("没有已知原因时，逐字显示引擎自己的说法")
    func unknownEndingShowsTheEnginesOwnWords() {
        let failed = outcome(exitCode: 2, message: "登录状态失效，请重新扫码")
        #expect(RunOutcomePresentation.title(failed) == "任务已结束")
        #expect(RunOutcomePresentation.detail(failed) == "登录状态失效，请重新扫码")
    }
}
