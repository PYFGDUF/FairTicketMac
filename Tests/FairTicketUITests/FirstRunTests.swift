import Testing
import FairTicketKit
@testable import FairTicketUI

/// What a first run tells a new user without writing them a paragraph.
///
/// These are the rules behind the sidebar's tick and dot, the page the window opens on,
/// and the chips beside the greyed-out 加入购物车 button.  All three exist to answer
/// "what now?" without adding prose to the interface, so the answer has to be exactly
/// right — a dot pointing at the wrong step is worse than no dot.
@MainActor
@Suite("首次上手")
struct FirstRunTests {

    // MARK: Where to start

    @Test("空草稿从购物车开始，然后依次是行程与乘车人")
    func stepsRunInOrder() {
        #expect(SetupProgress(done: []).next == .cart)
        #expect(SetupProgress(done: [.cart]).next == .trip)
        #expect(SetupProgress(done: [.cart, .trip]).next == .passengers)
        #expect(SetupProgress(done: [.cart, .trip, .passengers]).next == nil)
    }

    @Test("只标出一步是「下一步」，其余是待办或已完成")
    func onlyOneStepIsMarkedNext() {
        let progress = SetupProgress(done: [.cart])
        #expect(progress.state(for: .cart) == .done)
        #expect(progress.state(for: .trip) == .next)
        #expect(progress.state(for: .passengers) == .pending)
        // Optional tuning and the runtime readout are not steps, so they carry no mark.
        #expect(progress.state(for: .position) == .notAStep)
        #expect(progress.state(for: .advanced) == .notAStep)
        #expect(progress.state(for: .log) == .notAStep)
    }

    @Test("购物车里有备选就算这一步完成")
    func aFilledCartCompletesItsStep() {
        let model = AppModel.preview()
        model.setCart([
            CartItem(
                fromStation: "北京西", toStation: "郑州东",
                trainScope: CartItem.scopeAll, trainCode: "", seatType: "二等座"
            )
        ])
        let progress = SetupProgress(model: model)
        #expect(progress.state(for: .cart) == .done)
        #expect(progress.next != .cart)
    }

    // MARK: What the add button waits for

    private func draft(
        from: String = "北京西",
        to: String = "郑州东",
        scope: String = CartItem.scopeAll,
        code: String = "",
        seats: [String] = ["二等座"]
    ) -> AppModel.CartDraft {
        var draft = AppModel.CartDraft()
        draft.fromStation = from
        draft.toStation = to
        draft.trainScope = scope
        draft.trainCode = code
        draft.seatTypes = seats
        return draft
    }

    @Test("空草稿缺三样，顺序与视线一致")
    func emptyDraftListsEveryRequirement() {
        let missing = CartDraftRequirements.missing(
            in: draft(from: "", to: "", seats: [])
        )
        #expect(missing == [.fromStation, .toStation, .seat])
    }

    @Test("填齐了就不再要求任何东西")
    func completeDraftAsksForNothing() {
        #expect(CartDraftRequirements.missing(in: draft()).isEmpty)
    }

    @Test("「指定车次」没填车次时单独点名")
    func specificScopeNeedsATrainCode() {
        let missing = CartDraftRequirements.missing(
            in: draft(scope: CartItem.scopeSpecific, code: "  ")
        )
        #expect(missing == [.trainCode])
    }

    @Test("只有空格的站名不算填写")
    func whitespaceIsNotAFilledField() {
        let missing = CartDraftRequirements.missing(in: draft(from: "   ", to: "\t"))
        #expect(missing == [.fromStation, .toStation])
    }

    @Test("芯片用的是控件自己的字，不是另写一套说法")
    func chipLabelsMatchTheControls() {
        #expect(CartDraftField.fromStation.label == "出发站")
        #expect(CartDraftField.toStation.label == "到达站")
        #expect(CartDraftField.trainCode.label == "指定车次")
        #expect(CartDraftField.seat.label == "席别")
    }
}
