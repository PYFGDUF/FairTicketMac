import Foundation
import FairTicketKit

/// Exercises the sidecar transport without a window.
///
/// Mirrors the Python project's existing `--smoke-test` convention: it proves the
/// engine can be located, launched and driven, and it never logs in to 12306 or
/// submits an order — every command here is offline.
@main
enum SidecarProbe {

    static func main() async {
        do {
            try await run()
            print("\n探针完成：通道可用")
            exit(0)
        } catch {
            print("\n探针失败：\(error.localizedDescription)")
            exit(1)
        }
    }

    private static func run() async throws {
        // ---- locate -----------------------------------------------------
        let spec = try EngineLocator.resolve()
        print("=== 引擎定位 ===")
        print("形态        : \(spec.shape.rawValue)")
        print("来源        : \(spec.sourceDescription)")
        print("可执行文件  : \(spec.executableURL.path)")
        print("参数        : \(spec.arguments.joined(separator: " "))")
        print("工作目录    : \(spec.workingDirectoryURL.path)")

        let client = SidecarClient()
        defer { Task { await client.shutdown() } }

        // ---- handshake --------------------------------------------------
        let capabilities = try await client.launch(spec: spec)
        print("\n=== 握手 ===")
        print("协议版本    : \(capabilities.protocol)")
        print("引擎版本    : \(capabilities.engineVersion)")
        print("数据目录    : \(capabilities.dataDir)")
        print("可编辑项    : \(capabilities.editableKeys.count)")
        print("字段描述    : \(capabilities.fieldSpecs.count)")
        print("数值边界    : \(capabilities.numericRules.count)")
        print("分组顺序    : \(capabilities.groupOrder.joined(separator: " → "))")
        print("坐席        : \(capabilities.seatGroups.seated.joined(separator: " "))")
        print("卧铺        : \(capabilities.seatGroups.berth.joined(separator: " "))")
        print("车次范围    : \(capabilities.trainScopes.map(\.label).joined(separator: " / "))")
        print("票种        : \(capabilities.ticketTypes.map(\.label).joined(separator: " / "))")
        print("订单页      : \(capabilities.orderURL)")

        // The form is generated from field specs, so spot-check the shapes a
        // renderer branches on rather than trusting the counts alone.
        if let cart = capabilities.spec(for: "cart_items") {
            print("购物车字段  : kind=\(cart.kind.rawValue) group=\(cart.group)")
        }
        if let ticketTypes = capabilities.spec(for: "passenger_ticket_types") {
            print("票种字段    : kind=\(ticketTypes.kind.rawValue) group=\(ticketTypes.group)")
        }
        if let startAt = capabilities.spec(for: "start_at") {
            print("开始时间    : kind=\(startAt.kind.rawValue) 关闭项=\(startAt.optionalToggle)")
        }
        if let retries = capabilities.spec(for: "max_retries") {
            let low = retries.minimum.map { String($0) } ?? "?"
            let high = retries.maximum.map { String($0) } ?? "?"
            let step = retries.step.map { String($0) } ?? "?"
            print("最大轮数    : kind=\(retries.kind.rawValue) 范围=\(low)–\(high) 步长=\(step)")
        }

        // ---- validation -------------------------------------------------
        var broken = capabilities.initialState
        broken["cart_items"] = .array([
            CartItem(fromStation: "假的站", toStation: "郑州东", seatType: "二等座").json
        ])
        broken["train_date"] = .string("1999-01-01")
        broken["passenger_names"] = .array([])
        broken["auto_submit"] = .bool(true)

        let badResult = try await client.validate(broken)
        print("\n=== 校验（故意填错）===")
        print("valid       : \(badResult.valid)")
        for key in badResult.errors.keys.sorted() {
            print("  \(key.padding(toLength: 28, withPad: " ", startingAt: 0))\(badResult.errors[key] ?? "")")
        }

        var good = capabilities.initialState
        good["train_date"] = .string("2099-01-01")
        good["passenger_names"] = .array([.string("张三")])
        good["cart_items"] = .array([
            CartItem(
                fromStation: "北京西",
                toStation: "郑州东",
                trainScope: CartItem.scopeSpecific,
                trainCode: "G79",
                seatType: "二等座"
            ).json
        ])
        let goodResult = try await client.validate(good)
        print("\n=== 校验（正确草稿）===")
        print("valid       : \(goodResult.valid)  错误数 \(goodResult.errors.count)")

        // ---- engine's own reading of the cart ---------------------------
        let preview = try await client.preview(good)
        print("\n=== 购物车预览（引擎口径）===")
        for row in preview.cartRows { print("  \(row)") }
        print("  \(preview.scopeSummary)")
        print("  \(preview.priorityPreview)")

        // ---- start is gated by validation -------------------------------
        let rejected = try await client.startTask(broken)
        print("\n=== 启动被校验拦住 ===")
        print("started     : \(rejected.started)  错误数 \(rejected.errors.count)")

        // ---- offline station list --------------------------------------
        let names = try await client.stations()
        print("\n=== 站点（离线）===")
        print("count       : \(names.count)  含北京西: \(names.contains("北京西"))")

        // ---- session reset ---------------------------------------------
        try await client.resetSession()
        print("\n=== 会话重置 ===\nok")

        // ---- event stream sanity ---------------------------------------
        // A rejected start must not emit engine frames, which doubles as a check
        // that the stream is attached and empty rather than silently broken.
        let stream = client.events()
        var received = 0
        let collector = Task {
            for await _ in stream { received += 1 }
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        collector.cancel()
        print("\n=== 事件流 ===\n启动前收到 \(received) 条事件（应为 0）")

        await client.shutdown()
        print("\n=== 关闭 ===\n已请求引擎退出")
    }
}