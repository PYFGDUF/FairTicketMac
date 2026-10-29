import Foundation
import Testing
import FairTicketKit
@testable import FairTicketUI

/// The countdown is the one number the whole tool exists for, and it is computed
/// from the engine's clock correction rather than from the Mac's clock.  That rule
/// is easy to break by using `Date()` out of habit, so it is asserted here.
@MainActor
@Suite("开售倒计时")
struct CountdownTests {

    @Test("时钟校正被加到本地时间上")
    func serverClockAddsTheOffset() {
        let model = AppModel.preview()
        model.apply(RuntimeEvent(
            rawKind: "clock_sync",
            data: ["offset_seconds": .number(0.18), "rtt_ms": .number(42)]
        ))

        let drift = model.serverNow - Date().timeIntervalSince1970
        #expect(abs(drift - 0.18) < 0.05, "服务器时间应比本地快 0.18s，实际 \(drift)")
        #expect(model.serverClockReady)
        #expect(model.clockRTTMilliseconds == 42)
    }

    @Test("未校时时按本地时间估算，不显示已校准")
    func uncalibratedClockFallsBackToLocal() {
        let model = AppModel.preview()

        #expect(!model.serverClockReady)
        #expect(abs(model.serverNow - Date().timeIntervalSince1970) < 0.05)
    }

    @Test("倒计时用校正后的服务器时间，而不是本地墙钟")
    func countdownUsesTheCorrectedClock() throws {
        let model = AppModel.preview()
        // The server is 2.5s ahead of this Mac.
        model.apply(RuntimeEvent(
            rawKind: "clock_sync",
            data: ["offset_seconds": .number(2.5)]
        ))

        // A release moment 60s ahead *of the server clock*.
        let target = model.serverNow + 60
        model.apply(RuntimeEvent(
            rawKind: "phase",
            data: ["phase": .string("querying"), "target_timestamp": .number(target)]
        ))

        let remaining = try #require(model.countdownToRelease)
        #expect(abs(remaining - 60) < 0.05, "应为 60s，实际 \(remaining)")

        // The point of the rule: the local clock is behind, so measuring against
        // `Date()` would answer 62.5 and fire the release two and a half seconds late.
        let naive = target - Date().timeIntervalSince1970
        #expect(abs(naive - remaining - 2.5) < 0.05, "本测试的前提是本地时钟比服务器慢 2.5s")
    }

    @Test("没有目标时刻时不显示倒计时")
    func noTargetMeansNoCountdown() {
        let model = AppModel.preview()
        model.apply(RuntimeEvent(rawKind: "phase", data: ["phase": .string("preparing")]))

        #expect(model.countdownToRelease == nil)
        #expect(model.targetTimestamp == nil)
    }

    @Test("已过开售时刻时倒计时钳到 0，不出现负数")
    func releasedMomentClampsAtZero() throws {
        let model = AppModel.preview()
        model.apply(RuntimeEvent(
            rawKind: "phase",
            data: ["phase": .string("querying"), "target_timestamp": .number(Date().timeIntervalSince1970 - 30)]
        ))

        let remaining = try #require(model.countdownToRelease)
        #expect(remaining == 0)
    }

    @Test("热身窗口进度来自引擎的两个时间戳")
    func warmUpProgressComesFromEngineTimestamps() {
        let model = AppModel.preview()
        let target = Date().timeIntervalSince1970 + 60
        let start = target - 120

        model.apply(RuntimeEvent(
            rawKind: "phase",
            data: ["phase": .string("querying"), "target_timestamp": .number(target)]
        ))
        model.apply(RuntimeEvent(
            rawKind: "query",
            data: [
                "attempt": .number(12),
                "interval_seconds": .number(0.05),
                "query_start_timestamp": .number(start),
            ]
        ))

        #expect(model.queryCount == 12)
        #expect(model.currentQueryInterval == 0.05)
        #expect(model.queryStartTimestamp == start)
        // Half of the 120s warm-up window has elapsed.
        let progress = (model.serverNow - start) / (target - start)
        #expect(abs(progress - 0.5) < 0.02, "热身进度应约等于 50%，实际 \(progress)")
    }

    @Test("任务开始前清空上一轮的目标时刻")
    func startingClearsThePreviousRun() {
        let model = AppModel.preview(scenario: .queueing)
        #expect(model.latestCandidate != nil)

        model.resetRunState()

        #expect(model.targetTimestamp == nil)
        #expect(model.queryStartTimestamp == nil)
        #expect(model.latestCandidate == nil)
        #expect(model.queryCount == 0)
        #expect(model.phase == .preparing)
    }
}