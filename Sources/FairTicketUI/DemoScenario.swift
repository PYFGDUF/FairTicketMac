import Foundation
import FairTicketKit

/// Scripted event timelines for reviewing the running-state UI.
///
/// A real run needs a scanned 12306 QR code, which put the most interesting visual
/// states — the live countdown, the warm-up track, a hit candidate, the queue stage,
/// the safe-stop exit — out of reach of any automated check.  These timelines are
/// pushed through the same reducer the engine's frames go through, so what gets
/// drawn is the real view code with real values; only the clock is ours.
///
/// Enabled by `FAIRTICKET_DEMO=<name>`, driven by `script/preview.sh --demo <name>`.
enum DemoScenario: String {
    case running
    case imminent
    case queueing
    case safeStop = "safestop"
    /// The login card while the code is on screen — `qr_ready` immediately followed
    /// by `qr_status: waiting`, which is the exact pair that used to make the code
    /// flash and vanish.  This scenario is the regression test for that.
    case login
    /// The same, after the phone confirmed: the code is gone and the slot says so.
    case loginDone = "logindone"

    static var requested: DemoScenario? {
        ProcessInfo.processInfo.environment["FAIRTICKET_DEMO"]
            .flatMap { DemoScenario(rawValue: $0.lowercased()) }
    }

    func events(now: Double = Date().timeIntervalSince1970) -> [RuntimeEvent] {
        switch self {
        case .login, .loginDone:
            var events = lead(target: nil) + [qrReady()]
            events.append(qrStatus("waiting", "等待扫码"))
            if self == .loginDone {
                events.append(qrStatus("confirmed", "登录成功"))
            }
            return events

        case .running:
            // Mid warm-up window: countdown far out, track a fifth filled.
            let target = now + 95
            return lead(target: target, queryStart: now - 20)
                + [queryEvent(attempt: 37, interval: 0.05),
                   cartItem("备选 1/2：北京西 → 郑州东 · G79 · 二等座"),
                   queryEmpty("备选 1 查询成功，当前没有可尝试的二等座")]

        case .imminent:
            // Inside the last minute: the hero switches to the amber signal.
            let target = now + 25
            return lead(target: target, queryStart: now - 40)
                + [queryEvent(attempt: 128, interval: 0.05),
                   cartItem("备选 1/2：北京西 → 郑州东 · G79 · 二等座")]

        case .queueing:
            // Released: track full, candidate found, a soft preference downgraded.
            let target = now - 4
            return lead(target: target, queryStart: now - 70)
                + [queryEvent(attempt: 214, interval: 0.08),
                   candidate(train: "G79", seat: "二等座", stock: "有", start: "07:11"),
                   preferenceFallback("12306 未开放座位关系选择；订单仍会提交，位置由系统分配"),
                   phase("submitting", "提交订单"),
                   phase("queueing", "排队出票"),
                   orderWait(12)]

        case .safeStop:
            // The terminal case the UI must block on, with the engine's own wording.
            let target = now - 4
            return lead(target: target, queryStart: now - 70)
                + [queryEvent(attempt: 214, interval: 0.08),
                   candidate(train: "G79", seat: "二等座", stock: "有", start: "07:11"),
                   phase("submitting", "提交订单"),
                   phase("queueing", "排队出票"),
                   RuntimeEvent(
                       rawKind: "exit",
                       message: "出票状态暂时无法确认，任务已停止以避免重复下单；请到 12306 官方订单页核对",
                       data: [
                           "exit_code": .number(1),
                           "safe_stop": .bool(true),
                           "exception_type": .string("ResponseFormatError"),
                           "cancelled": .bool(false),
                       ]
                   )]
        }
    }

    // MARK: Event builders

    /// Everything before the release moment: calibrated clock, session reuse, the
    /// warm-up wait.
    ///
    /// Both timestamps ride on the `waiting` phase frame, which is where the engine
    /// puts them and nowhere else (`runner.py::_waiting_phase`).  A fixture that
    /// attached them to `query`, as an earlier revision of this file did, would keep
    /// the warm-up track drawing in every demo while it stayed empty against a real
    /// engine — the demo would pass and the feature would be broken.
    ///
    /// `target` is nil while the release moment is unknown, which is the state the
    /// login card is shown in.
    private func lead(target: Double?, queryStart: Double? = nil) -> [RuntimeEvent] {
        var events: [RuntimeEvent] = [
            RuntimeEvent(
                rawKind: "clock_sync",
                data: ["offset_seconds": .number(0.18), "rtt_ms": .number(42)]
            ),
            phase("stations", "站点编码"),
            phase("login", "扫码登录"),
        ]
        guard let target else { return events }
        var waiting: [String: JSONValue] = ["target_timestamp": .number(target)]
        if let queryStart { waiting["query_start_timestamp"] = .number(queryStart) }
        events.append(RuntimeEvent(rawKind: "qr_status", data: ["status": .string("logged_in")]))
        events.append(phase("waiting", "等待热身窗口", extra: waiting))
        events.append(phase("querying", "高频查票中"))
        return events
    }

    /// The engine's own `qr_ready` payload, captured from a real login request and
    /// stored as a fixture.  `expires_at` is re-stamped at replay time so the
    /// countdown is sensible whenever the demo is run.
    ///
    /// Re-capture after a protocol change: start the sidecar, send `start` with a
    /// valid config, and store the `qr_ready` frame's `data` object here.
    private func qrReady() -> RuntimeEvent {
        var payload: [String: JSONValue] = [:]
        if
            let url = Bundle.module.url(forResource: "login-qr", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONDecoder().decode(JSONValue.self, from: data),
            let object = json.objectValue
        {
            payload = object
            payload["expires_at"] = .number(Date().timeIntervalSince1970 + 180)
        }
        return RuntimeEvent(
            rawKind: "qr_ready",
            message: "请使用 12306 APP 扫码并确认登录",
            data: payload
        )
    }

    private func qrStatus(_ status: String, _ message: String) -> RuntimeEvent {
        RuntimeEvent(rawKind: "qr_status", message: message, data: ["status": .string(status)])
    }

    private func phase(
        _ name: String,
        _ message: String,
        extra: [String: JSONValue] = [:]
    ) -> RuntimeEvent {
        var data = extra
        data["phase"] = .string(name)
        return RuntimeEvent(rawKind: "phase", message: message, data: data)
    }

    private func queryEvent(attempt: Int, interval: Double) -> RuntimeEvent {
        RuntimeEvent(rawKind: "query", data: [
            "attempt": .number(Double(attempt)),
            "interval_seconds": .number(interval),
            "max_retries": .number(500),
        ])
    }

    private func candidate(train: String, seat: String, stock: String, start: String) -> RuntimeEvent {
        RuntimeEvent(rawKind: "candidate", data: [
            "train": .string(train),
            "seat_label": .string(seat),
            // A 12306 display token, not a count: the engine forwards it untouched.
            "stock": .string(stock),
            "start_time": .string(start),
        ])
    }

    private func cartItem(_ message: String) -> RuntimeEvent {
        RuntimeEvent(rawKind: "cart_item", message: message)
    }

    private func queryEmpty(_ message: String) -> RuntimeEvent {
        RuntimeEvent(rawKind: "query_empty", message: message)
    }

    private func preferenceFallback(_ message: String) -> RuntimeEvent {
        RuntimeEvent(rawKind: "preference_fallback", message: message)
    }

    private func orderWait(_ seconds: Double) -> RuntimeEvent {
        RuntimeEvent(rawKind: "order_wait", data: ["wait_time": .number(seconds)])
    }
}