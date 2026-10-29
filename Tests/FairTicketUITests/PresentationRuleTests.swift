import Foundation
import SwiftUI
import Testing
import FairTicketKit
@testable import FairTicketUI

/// Presentation rules that are easy to get subtly wrong and impossible to verify by
/// looking at a still image: when the form is allowed to mark a field red, and when
/// the third column folds.
@MainActor
@Suite("界面规则")
struct PresentationRuleTests {

    // MARK: Backend contract
    //
    // The form is generated from the engine's own `field_specs`, so the risk is not a
    // wrong label — it is a field that exists on the backend and has no control at all.
    // Nothing on screen looks broken when that happens; the setting simply cannot be
    // changed.  These two tests are what turn that from an invisible omission into a
    // failing build.

    @Test("引擎声明的每个可编辑键都能在界面上编辑到")
    func everyEditableKeyHasAControl() {
        let model = AppModel.preview()
        guard let capabilities = model.capabilities else {
            Issue.record("快照没有加载，这条断言没有意义")
            return
        }

        let reachable = ConfigSection.reachableKeys(in: capabilities)
        let editable = Set(capabilities.editableKeys)
        let missing = editable.subtracting(reachable)

        #expect(
            missing.isEmpty,
            "这些后端字段在界面上没有任何控件：\(missing.sorted())"
        )
        // And the other direction: a section must not claim a key the engine does not
        // accept, which would put a control on screen whose value is silently dropped.
        let unknown = reachable.subtracting(editable)
        #expect(
            unknown.isEmpty,
            "这些界面控件对应的键后端并不接受：\(unknown.sorted())"
        )
    }

    @Test("每个字段描述都归到了一个会渲染的分组里")
    func everySpecLandsInARenderedGroup() {
        let model = AppModel.preview()
        guard let capabilities = model.capabilities else {
            Issue.record("快照没有加载，这条断言没有意义")
            return
        }

        // `DetailView` walks `group_order`; a spec whose group is missing from that
        // list is never built, however correct the spec itself is.
        for spec in capabilities.fieldSpecs {
            #expect(
                capabilities.groupOrder.contains(spec.group),
                "字段 \(spec.key) 的分组「\(spec.group)」不在 group_order 里，永远不会渲染"
            )
        }
    }

    @Test("引擎声明的日志级别客户端全都认识")
    func engineLogLevelsAllMap() {
        let model = AppModel.preview()
        guard let capabilities = model.capabilities else {
            Issue.record("快照没有加载，这条断言没有意义")
            return
        }

        // The log page's filter is built from `log_levels`.  A level the Swift enum
        // does not know is silently dropped from the menu, so a severity the engine can
        // emit becomes unfilterable — which is exactly what happened when the menu was
        // hard-coded to four levels and left CRITICAL out.
        for level in capabilities.logLevels {
            #expect(
                LogEntry.Level(rawValue: level) != nil,
                "客户端不认识引擎声明的日志级别 \(level)"
            )
        }
    }

    // MARK: Validation gate

    @Test("用户没要求检查时，引擎报的错不显示")
    func errorsStayHiddenUntilAsked() {
        let model = AppModel.preview()
        model.applyValidation(["passenger_names": "自动提交时请填写 1 到 5 位乘车人"], byRequest: false)

        // The engine did report it — the interface just does not accuse the user yet.
        #expect(!model.fieldErrors.isEmpty)
        #expect(model.visibleFieldError("passenger_names") == nil)
        #expect(model.visibleErrorCount(in: .passengers) == 0)
    }

    @Test("点过「检查配置」之后，标红才出现")
    func marksAppearAfterARequest() {
        let model = AppModel.preview()
        model.applyValidation(["passenger_names": "自动提交时请填写 1 到 5 位乘车人"], byRequest: true)

        #expect(model.visibleFieldError("passenger_names") != nil)
        #expect(model.visibleErrorCount(in: .passengers) == 1)
    }

    @Test("请求过一次之后，后续编辑的标红继续可见")
    func marksStayVisibleAfterTheFirstRequest() {
        let model = AppModel.preview()
        model.applyValidation([:], byRequest: true)
        // A debounced check that happens while the user types must not switch them off.
        model.applyValidation(["cart_items": "购物车第 1 项：请输入出发站"], byRequest: false)

        #expect(model.visibleFieldError("cart_items") == "购物车第 1 项：请输入出发站")
    }

    @Test("标红按页面归属统计")
    func errorCountsFollowTheSectionOwnership() {
        let model = AppModel.preview()
        model.applyValidation(
            ["passenger_names": "缺少乘车人", "cart_items": "请至少加入一个购物车备选"],
            byRequest: true
        )

        #expect(model.visibleErrorCount(in: .passengers) == 1)
        #expect(model.visibleErrorCount(in: .cart) == 1)
        #expect(model.visibleErrorCount(in: .advanced) == 0)
    }

    @Test("错误清空后标红随之消失")
    func marksClearWithTheErrors() {
        let model = AppModel.preview()
        model.applyValidation(["cart_items": "请至少加入一个购物车备选"], byRequest: true)
        #expect(model.visibleFieldError("cart_items") != nil)

        model.applyValidation([:], byRequest: false)

        #expect(model.visibleFieldError("cart_items") == nil)
        #expect(model.visibleErrorCount(in: .cart) == 0)
    }

    // MARK: Inspector folding

    @Test("窗口过窄时自动收起任务状态面板")
    func inspectorFoldsWhenTheWindowIsNarrow() {
        let ui = UIState.preview()
        #expect(ui.showInspector)

        ui.adaptInspectorToWindowWidth(Theme.inspectorCollapseWidth - 100)

        #expect(!ui.showInspector)
    }

    @Test("窗口变宽后面板自动回来")
    func inspectorReturnsWhenThereIsRoom() {
        let ui = UIState.preview()
        ui.adaptInspectorToWindowWidth(Theme.inspectorCollapseWidth - 80)
        #expect(!ui.showInspector)

        ui.adaptInspectorToWindowWidth(Theme.inspectorCollapseWidth + 200)

        #expect(ui.showInspector)
    }

    @Test("用户手动收起的面板不会被自动打开")
    func aManualHideIsRespected() {
        let ui = UIState.preview()
        ui.toggleInspector()
        #expect(!ui.showInspector)

        ui.adaptInspectorToWindowWidth(1600)

        #expect(!ui.showInspector, "窗口变宽不应推翻用户的选择")
    }

    @Test("窗口构建期的占位宽度被忽略")
    func placeholderWidthsAreIgnored() {
        let ui = UIState.preview()

        // A window reports sizes like this while it is being built; acting on one
        // would fold the inspector on a width the user never saw — and doing it during
        // AppKit's layout pass crashed the app.
        ui.adaptInspectorToWindowWidth(0)
        ui.adaptInspectorToWindowWidth(400)
        ui.adaptInspectorToWindowWidth(FairTicketWindow.minimumSize.width - 1)

        #expect(ui.showInspector)
    }

    @Test("手动收起后再收窄，不会留下自动标记")
    func manualHideDoesNotLeaveAnAutomaticFlag() {
        let ui = UIState.preview()
        ui.toggleInspector()          // manually hidden
        ui.adaptInspectorToWindowWidth(1000)  // still hidden, nothing to fold
        ui.adaptInspectorToWindowWidth(1600)  // widening must not reopen it

        #expect(!ui.showInspector)
    }

    // MARK: Motion

    @Test("Reduce Motion 去掉动画，但不去掉状态变化")
    func reduceMotionResolvesToNoAnimation() {
        // The distinction matters: setting the animation to nil lands the change
        // immediately, whereas skipping the change would leave the interface wrong.
        #expect(Theme.Motion.resolved(Theme.Motion.snappy, reduceMotion: true) == nil)
        #expect(Theme.Motion.resolved(Theme.Motion.snappy, reduceMotion: false) != nil)
    }

    @Test("动效默认开启，只在窗口根节点按系统设置关闭")
    func motionIsOnUnlessTheRootTurnsItOff() {
        // The default is what a view hosted outside the window sees — a SwiftUI preview
        // or the menu bar label.  Defaulting to off would silently strip every transition
        // from those, which is a much harder bug to notice than one extra animation.
        #expect(EnvironmentValues().motionEnabled)
    }

    @Test("摘要行身份可重复且能区分重复姓名")
    func summaryLineIDsAreDeterministicAndUnique() {
        let values = ["张三", "李四", "张三"]
        let first = SummaryLine.identify(values)
        let second = SummaryLine.identify(values)

        #expect(first.map(\.id) == second.map(\.id))
        #expect(Set(first.map(\.id)).count == values.count)
        #expect(first.map(\.text) == values)
    }

    // MARK: Sidebar tiers

    @Test("侧边栏三层分区覆盖全部页面，不重不漏")
    func sidebarTiersCoverEveryDestination() {
        let tiers = ConfigSection.essential + ConfigSection.optional + ConfigSection.runtime

        #expect(Set(tiers) == Set(ConfigSection.allCases))
        #expect(tiers.count == ConfigSection.allCases.count, "同一个页面不能落在两个分区里")
        // The tiers are also the ⌘1…⌘6 order, so regrouping must not silently renumber
        // the shortcuts the View menu advertises.
        #expect(tiers == ConfigSection.allCases)
    }

    @Test("重新分区后，每个归属字段仍能找到自己的页面")
    func tieringDoesNotOrphanFields() {
        // The window's hard rule: a field the backend adds must never become unreachable.
        // Re-tiering the sidebar is a presentation change and must not move ownership.
        for section in ConfigSection.configuration {
            for key in ConfigSection.keys(for: section) {
                #expect(ConfigSection.owning(key) == section, "\(key) 的归属页面被分区改动动了")
            }
        }
        #expect(ConfigSection.claimedKeys.contains("cart_items"))
        #expect(!ConfigSection.configuration.contains(.log), "日志页不拥有任何参数")
    }

    @Test("高级参数默认收起")
    func advancedGroupsStartCollapsed() {
        let ui = UIState.preview()

        // 高级参数 has working defaults, so its groups start closed and a first-time user
        // can close the window without ever opening one.  The seat chips have no such
        // switch: both families are shown outright inside the composer.
        #expect(ui.expandedAdvancedGroups.isEmpty)
    }

    @Test("「去选择卧铺席别」要真的把席别芯片带到眼前")
    func berthShortcutOpensTheComposer() {
        let ui = UIState.preview()
        ui.selectedSection = .position
        #expect(!ui.showsCartDraft)

        // Version 5 has no seat page, so jumping to 备选购物车 alone left the user on the
        // entry list with nothing to choose: the chips are inside the composer, which is
        // closed by default.
        ui.revealBerthSelection()
        #expect(ui.selectedSection == .cart)
        #expect(ui.showsCartDraft)
    }

    // MARK: Bottom bar

    @Test("底栏先说挡住路的那个状态")
    func readinessReportsTheBlockingStateFirst() {
        // An engine that never came up is the only state the user cannot work around, so
        // it outranks everything — including form errors they could fix but not act on.
        #expect(
            BottomBar.Readiness.of(engineReady: false, visibleErrors: 3, isRunning: false)
                == .engineNotReady
        )
        // While a task runs, the form's problems are not what that button will act on.
        #expect(
            BottomBar.Readiness.of(engineReady: true, visibleErrors: 3, isRunning: true)
                == .running
        )
        #expect(
            BottomBar.Readiness.of(engineReady: true, visibleErrors: 2, isRunning: false)
                == .needsAttention(2)
        )
        // No complaint at all: the app cannot claim "ready" before the engine has checked,
        // and the button that performs the check is right next to it.
        #expect(
            BottomBar.Readiness.of(engineReady: true, visibleErrors: 0, isRunning: false)
                == .ready
        )
    }

    // MARK: Floating panels
    //
    // The window's three overlays are mutually exclusive, and two of them are reached by
    // an ordinary button.  A gate that stays shut after a run is therefore not a visual
    // glitch but a dead control: 开始任务 and 管理购物车 stop answering with nothing on
    // screen to say why, and the form around them still looks usable.

    @Test("结束面板关掉之后，开始任务与管理购物车要重新按得动")
    func dismissingTheResultLeavesTheOtherPanelsReachable() {
        // Up front, the result panel is the only thing on top — its scrim owns the click.
        #expect(
            ContentView.FrontPanel.of(
                outcomeNeedsReview: true, hasPendingStart: true, showsCartManager: true
            ) == .result
        )
        // Read.  The run is not forgotten — `runState` still holds it and the inspector
        // still reports it — but nothing else may stay gated on it, because no path back
        // to `.idle` exists until a new run starts.
        #expect(
            ContentView.FrontPanel.of(
                outcomeNeedsReview: false, hasPendingStart: true, showsCartManager: false
            ) == .briefing
        )
        #expect(
            ContentView.FrontPanel.of(
                outcomeNeedsReview: false, hasPendingStart: false, showsCartManager: true
            ) == .manager
        )
        #expect(
            ContentView.FrontPanel.of(
                outcomeNeedsReview: false, hasPendingStart: false, showsCartManager: false
            ) == .none
        )
    }

    @Test("没读过结束面板时，菜单里的开始任务是灰的而不是点了没反应")
    func anUnreadResultDisablesTheStartCommand() {
        let model = AppModel.preview()
        model.apply(RuntimeEvent(
            rawKind: "exit",
            message: "任务结束",
            data: ["exit_code": .number(0)]
        ))
        #expect(model.outcomeNeedsReview)
        #expect(TaskCommandAvailability(model: model).canStart == false)

        model.acknowledgeOutcome()
        #expect(TaskCommandAvailability(model: model).canStart)
    }

    @Test("底栏只报用户已经被指出过的问题")
    func bottomBarCountsOnlyErrorsTheUserHasBeenShown() {
        let model = AppModel.preview()
        model.applyValidation(["passenger_names": "自动提交时请填写 1 到 5 位乘车人"], byRequest: false)

        // The engine reported it, but the interface has not accused the user yet — and the
        // bar must not do the accusing on its behalf.
        #expect(model.visibleErrorTotal == 0)

        model.applyValidation(["passenger_names": "自动提交时请填写 1 到 5 位乘车人"], byRequest: true)
        #expect(model.visibleErrorTotal == 1)
    }
}
