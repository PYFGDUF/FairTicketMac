import Foundation
import Testing
import FairTicketKit
@testable import FairTicketUI

/// Rules the macOS HIG work introduced, where the guideline is precise enough to assert.
///
/// The visual half of the audit — the menu bar that now exists, the context menus, the
/// contrast hairlines — is verified by looking at the running app; these are the parts
/// that are a *rule* rather than a look, and a rule that only lives in a view body is a
/// rule that regresses the next time the view is edited.
@MainActor
@Suite("macOS 规范")
struct MacOSGuidelineTests {

    // MARK: Menu enablement (HIG 1.3)

    @Test("引擎未就绪或任务在跑时不提供「开始任务」")
    func startIsOfferedOnlyWhenItCanRun() {
        let idle = AppModel.preview()
        #expect(idle.engineState.isReady)
        #expect(!idle.isRunning)

        let idleAvailability = TaskCommandAvailability(model: idle)
        #expect(idleAvailability.canStart)
        #expect(!idleAvailability.isRunning)

        let running = AppModel.preview(scenario: .running)
        #expect(running.isRunning)
        let runningAvailability = TaskCommandAvailability(model: running)
        #expect(!runningAvailability.canStart)
        #expect(runningAvailability.isRunning)
    }

    @Test("没有引擎时菜单里的开始与检查都是灰的，而不是点了没反应")
    func disconnectedEngineDisablesTheTaskCommands() {
        let offline = AppModel.preview(engineReady: false)
        let availability = TaskCommandAvailability(model: offline)
        #expect(!availability.canStart)
        #expect(!availability.isRunning)
    }

    @Test("订单入口跟着引擎给出的订单地址走")
    func orderEntryFollowsTheEngine() {
        let model = AppModel.preview()
        #expect(TaskCommandAvailability(model: model).hasOrder == (model.orderURL != nil))
    }

    // MARK: Sidebar movement (HIG 5.7)

    @Test("上下键按侧栏顺序走，并在两端停住")
    func arrowKeysWalkTheSidebarInOrder() {
        let order = ConfigSection.allCases
        #expect(order.first?.neighbour(offset: -1) == nil)
        #expect(order.last?.neighbour(offset: 1) == nil)
        for (index, section) in order.enumerated() {
            if index + 1 < order.count {
                #expect(section.neighbour(offset: 1) == order[index + 1])
            }
            if index > 0 {
                #expect(section.neighbour(offset: -1) == order[index - 1])
            }
        }
    }

    // MARK: Cart reordering, as the context menu spells it (HIG 1.4)

    private func model(count: Int) -> AppModel {
        let model = AppModel.preview()
        model.setCart((1...count).map {
            CartItem(
                fromStation: "站\($0)",
                toStation: "终点",
                trainScope: CartItem.scopeAll,
                trainCode: "",
                seatType: "二等座"
            )
        })
        return model
    }

    @Test("「下移一位」把这一项移到邻居后面")
    func moveDownLandsAfterTheNeighbour() {
        let model = model(count: 3)
        let items = model.cartItems
        model.moveCartItem(items[0].id, to: items[1].id)
        #expect(model.cartItems.map(\.fromStation) == ["站2", "站1", "站3"])
    }

    @Test("「上移一位」把这一项移到邻居前面")
    func moveUpLandsBeforeTheNeighbour() {
        let model = model(count: 3)
        let items = model.cartItems
        model.moveCartItem(items[2].id, to: items[1].id)
        #expect(model.cartItems.map(\.fromStation) == ["站1", "站3", "站2"])
    }

    @Test("「移到最前」只动这一项")
    func moveToTopKeepsTheRestInOrder() {
        let model = model(count: 3)
        let items = model.cartItems
        model.moveCartItem(items[2].id, to: items[0].id)
        #expect(model.cartItems.map(\.fromStation) == ["站3", "站1", "站2"])
    }

    // MARK: Links (HIG 1.1 — the Help menu)

    @Test("帮助菜单的地址都是 ASCII，中文文件名已经转义")
    func helpLinksAreEncodedForAURLLiteral() {
        for url in [
            FairTicketProject.documentationURL,
            FairTicketProject.principleURL,
            FairTicketProject.issuesURL,
            FairTicketProject.repositoryURL,
            FairTicketProject.railwayURL,
        ] {
            let text = url.absoluteString
            #expect(text.allSatisfy { $0.isASCII }, "地址里有未转义字符：\(text)")
            #expect(text.hasPrefix("https://"))
        }
        // The two documents are the ones whose file names are Chinese, so they are where
        // a missing escape would show up.
        #expect(FairTicketProject.documentationURL.absoluteString.contains("%"))
        #expect(FairTicketProject.principleURL.absoluteString.contains("%"))
        #expect(FairTicketProject.issuesURL.absoluteString.hasSuffix("issues/new"))
    }
}
