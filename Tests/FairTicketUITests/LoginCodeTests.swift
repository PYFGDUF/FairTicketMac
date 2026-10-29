import Foundation
import Testing
import FairTicketKit
@testable import FairTicketUI

/// The login card's rules.
///
/// Written after a real bug: the code appeared and vanished within a frame, because
/// the reducer cleared the image on any status that was not `logged_in` — and the
/// engine sends `qr_ready` followed immediately by `qr_status: waiting`.  These
/// assertions replace the screenshot that only caught it by luck.
@MainActor
@Suite("登录二维码")
struct LoginCodeTests {

    @Test("二维码到达后紧跟 waiting，图片必须保留")
    func codeSurvivesTheWaitingStatus() throws {
        let model = AppModel.preview(scenario: .login)

        let data = try #require(model.qrImageData, "二维码图片被清空了")
        #expect(data.count > 1000, "二维码不应是空图片")
        #expect(model.showsLoginCode)
        #expect(model.qrStatus == .waiting)
        #expect(model.qrExpiresAt != nil, "有效期丢失会让倒计时无处可算")
    }

    @Test("已扫码（scanned）时仍然保留图片")
    func codeSurvivesScanned() {
        let model = AppModel.preview()
        model.apply(qrReady())
        model.apply(qrStatus(.scanned))

        #expect(model.qrStatus == .scanned)
        #expect(model.showsLoginCode)
    }

    @Test("手机确认登录后清空图片，并说明原因")
    func codeClearsWhenConfirmed() {
        let model = AppModel.preview(scenario: .loginDone)

        #expect(model.qrStatus == .confirmed)
        #expect(!model.showsLoginCode)
        #expect(model.loginSlot.text == "登录成功")
    }

    @Test("二维码过期后清空图片，并说明新码会来")
    func codeClearsWhenExpired() {
        let model = AppModel.preview()
        model.apply(qrReady())
        model.apply(qrStatus(.expired))

        #expect(!model.showsLoginCode)
        #expect(model.loginSlot.systemImage == "arrow.clockwise")
        // The engine now replaces the code inside the same run, so the copy must not
        // send the user off to restart the task.
        #expect(model.loginSlot.text.contains("过期"))
        #expect(model.loginSlot.text.contains("正在获取新二维码"))
    }

    @Test("会话仍然有效时不显示二维码")
    func loggedInSessionShowsNoCode() {
        let model = AppModel.preview()
        model.apply(qrStatus(.loggedIn))

        #expect(!model.showsLoginCode)
        #expect(model.loginSlot.text.contains("已登录"))
    }

    @Test("未开始任务时插槽为空态文案")
    func idleSlotExplainsItself() {
        let model = AppModel.preview()

        #expect(model.qrStatus == nil)
        #expect(!model.showsLoginCode)
        #expect(model.loginSlot.systemImage == "qrcode")
        #expect(model.loginSlot.text.contains("开始任务后"))
    }

    @Test("下单成功后不再显示二维码")
    func codeClearsAfterAnOrder() {
        let model = AppModel.preview(scenario: .login)
        #expect(model.showsLoginCode)

        model.apply(RuntimeEvent(rawKind: "order_success", data: ["order_id": .string("E123456789")]))

        #expect(!model.showsLoginCode)
        #expect(model.orderID == "E123456789")
    }

    // MARK: Fixtures

    /// The engine's real `qr_ready` payload, replayed with a fresh expiry.
    private func qrReady() -> RuntimeEvent {
        DemoScenario.login.events().first { $0.rawKind == "qr_ready" } ?? RuntimeEvent(rawKind: "qr_ready")
    }

    private func qrStatus(_ status: RuntimeEvent.QRStatus) -> RuntimeEvent {
        RuntimeEvent(rawKind: "qr_status", data: ["status": .string(status.rawValue)])
    }
}