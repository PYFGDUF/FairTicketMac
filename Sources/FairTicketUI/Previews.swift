import SwiftUI
import FairTicketKit

// Previews, in the library target on purpose: SwiftUI Previews do not run inside an
// executable target, which is the reason the interface was moved out of the app.
//
// Every preview here is backed by the captured capabilities snapshot, so the canvas
// renders the real form, the real seat table and the real group order without
// launching Python.  Re-capture the snapshot after a backend field change — see
// `CapabilitiesSnapshot`.

// MARK: - Whole window

#Preview("窗口 · 备选购物车") {
    WindowPreview(section: .cart)
}

#Preview("窗口 · 行程时间（浅色）") {
    WindowPreview(section: .trip)
}

#Preview("窗口 · 行程时间（深色）") {
    WindowPreview(section: .trip)
        .preferredColorScheme(.dark)
}

#Preview("窗口 · 乘车人") {
    WindowPreview(section: .passengers)
}

#Preview("窗口 · 座位与铺位") {
    WindowPreview(section: .position)
}

#Preview("窗口 · 高级参数") {
    WindowPreview(section: .advanced)
}

#Preview("窗口 · 运行中") {
    WindowPreview(section: .cart, scenario: .running)
}

#Preview("窗口 · 排队出票") {
    WindowPreview(section: .cart, scenario: .queueing)
}

// MARK: - Task status

#Preview("状态 · 空闲") {
    InspectorPreview(scenario: nil)
}

#Preview("状态 · 开售前 1 分钟（amber）") {
    InspectorPreview(scenario: .imminent)
}

#Preview("状态 · 深色 · 排队出票") {
    InspectorPreview(scenario: .queueing)
        .preferredColorScheme(.dark)
}

// MARK: - Components

#Preview("全部字段控件") {
    AllFieldsGallery()
}

#Preview("组件 · 卡片与提示") {
    ComponentGallery()
}

#Preview("组件 · 指标") {
    HStack(spacing: 0) {
        MetricTile(name: "查询", value: "214", unit: "次")
        Divider().frame(height: 30)
        MetricTile(name: "RTT", value: "42", unit: "ms")
        Divider().frame(height: 30)
        MetricTile(name: "时钟偏移", value: "0.183", unit: "s")
    }
    .cardSurface()
    .frame(width: Theme.inspectorWidth)
    .padding(Theme.Space.lg)
}

// MARK: - Editors

#Preview("备选购物车编辑器") {
    EditorPreview(section: .cart) {
        CartEditor(spec: .stub("cart_items"))
    }
}

#Preview("添加备选") {
    EditorPreview(section: .cart) {
        CartDraftCard()
    }
}

#Preview("乘车人与票种") {
    EditorPreview(section: .passengers) {
        PassengerRosterEditor()
    }
}

#Preview("座位关系图") {
    EditorPreview(section: .position) {
        SeatMapEditor(spec: .stub("seat_position_preferences"))
    }
}

#Preview("铺位数量") {
    EditorPreview(section: .position) {
        BerthCountEditor(spec: .stub("berth_preference"))
    }
}

// MARK: - Logs

#Preview("日志页") {
    LogPreview()
}

// MARK: - Start confirmation

#Preview("启动确认") {
    StartConfirmationView(
        summary: StartSummary(
            route: "北京西 → 郑州东",
            date: "2026-09-28",
            passengers: "张三、李四",
            cartRows: [
                "1. 北京西 → 郑州东 · G79 · 二等座",
                "2. 北京西 → 郑州东 · G95 · 一等座",
                "3. 北京西 → 郑州东 · 不限车次 · 硬卧",
            ],
            scopeSummary: "共 3 个备选 · 1 组站对 · 3 种席别",
            attemptOrder: "按购物车顺序依次尝试；任意一项成功出票后，其余备选停止。",
            position: "座位关系 A/F；下/中/上铺 1/0/0",
            mode: "自动提交"
        ),
        onConfirm: {},
        onCancel: {}
    )
}

#Preview("启动确认 · 仅监控（深色）") {
    StartConfirmationView(
        summary: StartSummary(
            route: "北京西 → 郑州东",
            date: "2026-09-28",
            passengers: "仅监控",
            cartRows: ["1. 北京西 → 郑州东 · 不限车次 · 二等座"],
            scopeSummary: "共 1 个备选 · 1 组站对 · 1 种席别 · 其中 1 项不限车次",
            attemptOrder: "按购物车顺序依次尝试；任意一项成功出票后，其余备选停止。",
            position: "无启用的偏好",
            mode: "仅监控"
        ),
        onConfirm: {},
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}

// MARK: - Preview scaffolding
//
// Small wrappers rather than statements inside the `#Preview` closure: the macro's
// body is a view builder, so seeding state has to happen in an initialiser or a
// `task`, not as a bare statement.

private struct WindowPreview: View {
    @StateObject private var model: AppModel
    @StateObject private var ui: UIState

    init(section: ConfigSection, scenario: DemoScenario? = nil) {
        _model = StateObject(wrappedValue: AppModel.preview(scenario: scenario))
        _ui = StateObject(wrappedValue: UIState.preview(section: section))
    }

    var body: some View {
        ContentView()
            .environmentObject(model)
            .environmentObject(ui)
            .frame(width: 1420, height: 880)
    }
}

private struct InspectorPreview: View {
    @StateObject private var model: AppModel
    @StateObject private var ui = UIState()

    init(scenario: DemoScenario?) {
        _model = StateObject(wrappedValue: AppModel.preview(scenario: scenario))
    }

    var body: some View {
        InspectorView()
            .environmentObject(model)
            // The idle panel's empty state can jump to 行程, so it needs the same
            // presentation state the window gives it.
            .environmentObject(ui)
            .frame(width: Theme.inspectorWidth, height: 820)
    }
}

/// Every backend field, in order: the cheapest way to spot a control that no longer
/// matches the rest — a stray radius, a wrong unit, a missing error state.
private struct AllFieldsGallery: View {
    @StateObject private var model = AppModel.preview()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                ForEach(model.capabilities?.fieldSpecs ?? []) { spec in
                    FieldRow(spec: spec)
                }
            }
            .padding(Theme.Space.lg)
            .frame(width: 520)
        }
        .environmentObject(model)
        // One invalid cart entry so the composite error state is on screen too.
        .task {
            model.cartDraft.fromStation = "不存在的站名"
            model.cartDraft.seatTypes = ["二等座"]
            model.commitCartDraft()
        }
    }
}

private struct ComponentGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Card(title: "分组标题", marker: "必填") {
                    Text("内容区").font(.caption)
                }
                Card {
                    HStack(spacing: Theme.Space.sm) {
                        StatusPill(text: "运行中", tint: Theme.brand)
                        StatusPill(text: "已安全停止", tint: Theme.brand)
                        StatusPill(text: "出票成功", tint: .green, systemImage: "checkmark.circle.fill")
                        CountChip(text: "12 项")
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        InlineNote(text: "中性说明：车次留空时不限类型。")
                        InlineNote(text: "品牌说明：实际车次范围由引擎决定。", tone: .brand)
                        InlineNote(text: "警告：位置偏好无法满足，订单仍会提交。", tone: .warning)
                        EngineTextBlock(text: "车次优先：G1（示例）二等座 → G1（示例）硬座 → K1（示例）二等座")
                    }
                }
            }
            .padding(Theme.Space.lg)
            .frame(width: 520)
        }
    }
}

private struct EditorPreview<Content: View>: View {
    @StateObject private var model = AppModel.preview()
    @StateObject private var ui: UIState
    private let content: Content

    init(section: ConfigSection, @ViewBuilder content: () -> Content) {
        _ui = StateObject(wrappedValue: UIState.preview(section: section))
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .padding(Theme.Space.lg)
                .frame(width: 520)
        }
        .environmentObject(model)
        .environmentObject(ui)
    }
}

private struct LogPreview: View {
    @StateObject private var model = AppModel.preview(scenario: .queueing)
    @StateObject private var ui = UIState.preview(section: .log)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            LogPageView()
        }
        .padding(Theme.Space.lg)
        .frame(width: 900)
        .environmentObject(model)
        .environmentObject(ui)
        .task { model.seedPreviewLog() }
    }
}

/// Field specs are generated by the engine at handshake; the editors only read the
/// key, so a stub carrying that key is enough to preview one in isolation.
extension FieldSpec {
    static func stub(_ key: String) -> FieldSpec {
        let json = """
        {"key": "\(key)", "label": "\(key)", "page": "basic", "group": "预览",
         "kind": "text", "help": "", "placeholder": "", "decimals": 0, "suffix": "",
         "options": [], "optional_toggle": "", "inline_label": "", "dormant_until": ""}
        """
        // Force-unwrapped: a malformed literal is a bug in this file, and the preview
        // should fail loudly rather than render an empty editor.
        return try! JSONDecoder().decode(FieldSpec.self, from: Data(json.utf8))
    }
}