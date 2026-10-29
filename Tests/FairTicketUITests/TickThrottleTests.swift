import Combine
import Foundation
import Testing
import FairTicketKit
@testable import FairTicketUI

/// The ticker exists to advance the two readouts that come from the clock, and its
/// publishing rate is a performance contract rather than a detail: `@Published` fires
/// on assignment, not on change, so a ticker that publishes every wake-up re-renders
/// the whole window every wake-up.  That version measured ~100% of one core with the
/// app sitting idle, and nothing on screen looked wrong — which is exactly why the
/// rate is asserted here.
@MainActor
@Suite("刷新节流")
struct TickThrottleTests {

    /// Counts `objectWillChange` emissions.  A class rather than a captured local
    /// because the publisher's closure escapes; delivery is synchronous on the main
    /// actor, so the access is not actually concurrent.
    private final class Emissions: @unchecked Sendable {
        var count = 0
    }

    private func emissions(from model: AppModel, ticking times: Int) -> Int {
        let counter = Emissions()
        let token = model.objectWillChange.sink { _ in counter.count += 1 }
        for _ in 0..<times { model.tickCountdown() }
        token.cancel()
        return counter.count
    }

    @Test("空闲窗口的 ticker 一次都不发布")
    func idleWindowNeverPublishes() {
        // No release moment and no QR code: nothing on screen is derived from the
        // clock, so ten wakes must produce no re-render at all.
        let model = AppModel.preview()

        #expect(model.tickKey(countdown: nil) == nil)
        #expect(emissions(from: model, ticking: 10) == 0)
    }

    @Test("倒计时按整秒发布，十分位交给面板自己的时钟")
    func countdownPublishesAtWholeSeconds() throws {
        let model = AppModel.preview()

        // Everything that reads `remainingSeconds` prints whole seconds — the menu bar
        // and the hero's amber switch.  The tenths digit belongs to the hero, which
        // runs its own `TimelineView`, so the window-wide tick stays at one hertz.
        let quantised = try #require(model.tickKey(countdown: 59.94))
        #expect(quantised == 59)
        #expect(model.tickKey(countdown: 59.14) == 59, "同一秒内的两个读数只能发布一次")
        #expect(model.tickKey(countdown: 3661.4) == 3661)
    }

    @Test("面板自己的时钟用引擎校正过的时间")
    func heroClockUsesTheCorrectedTime() throws {
        let model = AppModel.preview()
        model.apply(RuntimeEvent(
            rawKind: "clock_sync",
            data: ["offset_seconds": .number(2.5)]
        ))
        // A release moment 60s ahead of the *server* clock.
        let target = model.serverNow + 60
        model.apply(RuntimeEvent(
            rawKind: "phase",
            data: ["phase": .string("querying"), "target_timestamp": .number(target)]
        ))

        // The hero asks for a reading at a specific instant, so a fixed date has to give
        // a fixed answer — and it must include the offset, or the tenths would be two
        // and a half seconds out.
        let reading = Date()
        let fromDate = try #require(model.countdown(at: reading))
        let expected = target - (reading.timeIntervalSince1970 + 2.5)
        #expect(abs(fromDate - expected) < 0.001)
    }

    @Test("面板自己决定重绘速度：空闲不重绘，最后一分钟才十赫兹")
    func heroCadenceFollowsTheWait() {
        // Nothing counting: no redraw worth scheduling.  `TimelineView` has no stopped
        // schedule, so the slowest one stands in — the readout is a constant then.
        #expect(InspectorView.Cadence.forRemaining(nil) == .idle)
        #expect(InspectorView.Cadence.forRemaining(0) == .idle, "已开售就不再变化，没有重绘的理由")
        #expect(InspectorView.Cadence.forRemaining(-5) == .idle)

        // Whole seconds are all the readout shows, so one hertz is the whole story.
        #expect(InspectorView.Cadence.forRemaining(3600) == .seconds)
        #expect(InspectorView.Cadence.forRemaining(61) == .seconds)

        // The last minute is the only stretch where tenths are information.
        #expect(InspectorView.Cadence.forRemaining(60) == .tenths)
        #expect(InspectorView.Cadence.forRemaining(0.4) == .tenths)

        #expect(InspectorView.Cadence.idle.redrawInterval == 60)
        #expect(InspectorView.Cadence.seconds.redrawInterval == 1)
        #expect(InspectorView.Cadence.tenths.redrawInterval == 0.1)
    }

    @Test("读数精度跟随重绘速度，不显示已过期的十分位")
    func readoutPrecisionFollowsCadence() {
        #expect(InspectorView.readout(nil) == "--:--:--")

        // Outside the last minute the panel redraws once a second, so a tenths digit
        // would be stale the moment it was drawn.
        #expect(InspectorView.readout(90.4) == "01:30")
        #expect(InspectorView.readout(3661.4) == "01:01:01")
        #expect(InspectorView.readout(0) == "00:00", "已开售显示 00:00，不出现负数")

        // Inside it, tenths are the point.
        #expect(InspectorView.readout(59.94) == "00:59.9")
        #expect(InspectorView.readout(9.05) == "00:09.0")
    }

    @Test("等待扫码时 ticker 一次都不发布")
    func waitingForScanNeverPublishes() {
        let model = AppModel.preview()
        // `qr_ready` is what carries `expires_at`, and it leaves the status at `waiting`.
        model.apply(RuntimeEvent(
            rawKind: "qr_ready",
            data: ["expires_at": .number(Date().timeIntervalSince1970 + 90)]
        ))

        // The code's expiry counts down in the card that shows it, on its own clock.
        // Publishing for it here would rebuild the whole window once a second for a
        // readout in one label — which is what this asserts is not happening.
        #expect(model.tickKey(countdown: nil) == nil)
        #expect(emissions(from: model, ticking: 10) == 0)
    }
}